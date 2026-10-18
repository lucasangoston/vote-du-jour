import 'dart:convert';

import 'package:archive/archive.dart';

import 'dump_source.dart';
import 'object_store.dart';

/// Archive des députés, sénateurs, ministres et organes de la 17e législature
/// (Licence Ouverte, ~3 Mo), régénérée une fois par jour. Contrairement à
/// l'archive des seuls députés en exercice, elle garde les groupes dissous ou
/// renommés en cours de législature (par exemple `PO847173`, « UDR » jusqu'au
/// 4 septembre 2025), que citent les anciens scrutins.
const organesDumpUrl =
    'https://data.assemblee-nationale.fr/static/openData/repository/17/amo/deputes_senateurs_ministres_legislature/AMO20_dep_sen_min_tous_mandats_et_organes.json.zip';

/// Clé de l'état des groupes politiques dans le bucket : le `Last-Modified`
/// du dernier jeu de données des organes et l'annuaire qui en a été tiré.
const organesStateKey = 'state/organes.json';

/// Nom affiché pour un groupe absent de l'open data (l'archive des scrutins
/// cite parfois un organe `PO0`).
const unknownGroupName = 'Groupe non identifié';

/// Un groupe politique de l'Assemblée.
class PoliticalGroup {
  const PoliticalGroup({
    required this.uid,
    required this.name,
    this.abbreviation,
  });

  /// Référence officielle (organe), par exemple `PO845401`.
  final String uid;

  /// Nom complet (`libelle`), par exemple « Rassemblement National ».
  final String name;

  /// Sigle d'usage (`libelleAbrege`), par exemple « RN » ou « EcoS ».
  final String? abbreviation;
}

/// Annuaire des groupes politiques (organes de type `GP`), pour donner un nom
/// lisible aux votes par groupe des scrutins, qui ne citent que la référence
/// de l'organe.
class GroupDirectory {
  GroupDirectory(Map<String, PoliticalGroup> groups) : _groups = groups;

  final Map<String, PoliticalGroup> _groups;

  /// Nombre de groupes connus.
  int get length => _groups.length;

  PoliticalGroup? operator [](String uid) => _groups[uid];

  /// Lit l'archive des acteurs et organes (`json/organe/<uid>.json`) et garde
  /// les groupes politiques. Un organe illisible est ignoré : il ne sert qu'à
  /// nommer un groupe, qui gardera sinon sa référence.
  factory GroupDirectory.fromArchive(List<int> zipBytes) {
    final groups = <String, PoliticalGroup>{};
    for (final file in ZipDecoder().decodeBytes(zipBytes)) {
      final name = file.name.toLowerCase();
      if (!file.isFile || !name.endsWith('.json')) continue;
      if (!name.contains('organe/')) continue;
      if (parseOrganeJson(utf8.decode(file.content)) case final group?) {
        groups[group.uid] = group;
      }
    }
    if (groups.isEmpty) {
      throw const FormatException('Organes : aucun groupe politique trouvé');
    }
    return GroupDirectory(groups);
  }

  /// Relit un annuaire enregistré par [toJson]. Lève [FormatException] s'il
  /// est illisible.
  factory GroupDirectory.fromJson(Object? json) {
    if (json is! Map<String, Object?> || json['version'] != _cacheVersion) {
      throw const FormatException('Annuaire des groupes : version inattendue');
    }
    final groups = json['groups'];
    if (groups is! Map<String, Object?>) {
      throw const FormatException('Annuaire des groupes : objet attendu');
    }
    return GroupDirectory({
      for (final MapEntry(:key, :value) in groups.entries)
        if (value is Map<String, Object?> && value['name'] is String)
          key: PoliticalGroup(
            uid: key,
            name: value['name'] as String,
            abbreviation: value['abbreviation'] as String?,
          ),
    });
  }

  static const _cacheVersion = 1;

  Map<String, Object?> toJson() => {
    'version': _cacheVersion,
    'groups': {
      for (final uid in _groups.keys.toList()..sort())
        uid: {
          'name': _groups[uid]!.name,
          'abbreviation': ?_groups[uid]!.abbreviation,
        },
    },
  };
}

/// Lit le JSON d'un organe ; renvoie le groupe s'il s'agit d'un groupe
/// politique (`codeType` `GP`), sinon `null`.
PoliticalGroup? parseOrganeJson(String json) {
  try {
    final organe = (jsonDecode(json) as Map<String, Object?>)['organe'];
    if (organe is! Map<String, Object?> || organe['codeType'] != 'GP') {
      return null;
    }
    final uid = organe['uid'];
    final name = organe['libelle'];
    if (uid is! String || name is! String || name.trim().isEmpty) return null;
    final abbreviation = organe['libelleAbrege'] ?? organe['libelleAbrev'];
    return PoliticalGroup(
      uid: uid,
      name: name.trim(),
      abbreviation: abbreviation is String && abbreviation.trim().isNotEmpty
          ? abbreviation.trim()
          : null,
    );
  } on Object {
    return null;
  }
}

/// Annuaire des groupes à utiliser pour cette exécution du job.
class GroupDirectoryLoad {
  const GroupDirectoryLoad._(this.directory, {this.pendingState});

  /// Annuaire à jour, ou dernier connu, ou `null` si aucun n'est disponible
  /// (les groupes gardent alors le nom [unknownGroupName]).
  final GroupDirectory? directory;

  /// État à enregistrer une fois les décisions republiées.
  final String? pendingState;

  /// Les noms des groupes ont changé depuis la dernière publication : les
  /// fichiers de détail doivent être reconstruits même si les scrutins n'ont
  /// pas changé.
  bool get changed => pendingState != null;

  /// Enregistre le nouvel état, après la publication.
  Future<void> save(ObjectStore store) async {
    if (pendingState case final state?) {
      await store.write(organesStateKey, state, cacheControl: 'no-store');
    }
  }
}

/// Charge l'annuaire des groupes : télécharge le jeu de données des organes
/// s'il a changé depuis l'état enregistré, sinon relit l'annuaire en cache.
///
/// Un nouveau jeu de données dont les groupes n'ont pas changé (le cas
/// courant : il est régénéré chaque nuit) ne fait rien republier ; son
/// `Last-Modified` est enregistré tout de suite. En cas d'échec, le dernier
/// annuaire connu sert et un avertissement est ajouté à [warnings].
Future<GroupDirectoryLoad> loadGroupDirectory({
  required DumpSource? source,
  required ObjectStore store,
  required List<String> warnings,
  required DateTime now,
  bool force = false,
}) async {
  if (source == null) return const GroupDirectoryLoad._(null);
  final cached = await _readState(store, warnings);
  try {
    final fetch = await source.fetch(
      ifModifiedSince: force ? null : cached?.lastModified,
    );
    switch (fetch) {
      case DumpNotModified():
        return GroupDirectoryLoad._(cached?.directory);
      case DumpDownloaded(:final bytes, :final lastModified):
        final directory = GroupDirectory.fromArchive(bytes);
        final groups = jsonEncode(directory.toJson());
        final state = jsonEncode({
          'lastModified': lastModified,
          'processedAt': now.toUtc().toIso8601String(),
          'directory': directory.toJson(),
        });
        final unchanged =
            cached != null && jsonEncode(cached.directory.toJson()) == groups;
        if (unchanged && !force) {
          await store.write(organesStateKey, state, cacheControl: 'no-store');
          return GroupDirectoryLoad._(directory);
        }
        return GroupDirectoryLoad._(directory, pendingState: state);
    }
  } on Exception catch (e) {
    final fallback = cached != null
        ? 'dernier annuaire connu utilisé'
        : 'groupes non nommés';
    warnings.add('organes (groupes politiques) indisponibles, $fallback ($e)');
    return GroupDirectoryLoad._(cached?.directory);
  }
}

Future<({String? lastModified, GroupDirectory directory})?> _readState(
  ObjectStore store,
  List<String> warnings,
) async {
  final raw = await store.read(organesStateKey);
  if (raw == null) return null;
  try {
    final json = jsonDecode(raw) as Map<String, Object?>;
    return (
      lastModified: json['lastModified'] as String?,
      directory: GroupDirectory.fromJson(json['directory']),
    );
  } on Object catch (e) {
    warnings.add('état des organes illisible, il sera reconstruit ($e)');
    return null;
  }
}
