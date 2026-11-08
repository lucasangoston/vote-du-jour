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
    this.place,
    this.color,
  });

  /// Référence officielle (organe), par exemple `PO845401`.
  final String uid;

  /// Nom complet (`libelle`), par exemple « Rassemblement National ».
  final String name;

  /// Sigle d'usage (`libelleAbrege`), par exemple « RN » ou « EcoS ».
  final String? abbreviation;

  /// Place moyenne des membres du groupe dans l'hémicycle (#67) : moyenne
  /// des numéros de siège (`placeHemicycle`) des députés en exercice, arrondie
  /// au dixième. Les sièges sont numérotés de la droite de l'hémicycle (1) vers
  /// sa gauche (650) : plus la place est grande, plus le groupe siège à
  /// gauche. Pour un groupe dissous ou renommé, la place actuelle de ses
  /// anciens membres. `null` si aucun siège n'est connu.
  final double? place;

  /// Couleur officielle (`couleurAssociee`, #71), au format `#RRGGBB`, si
  /// l'open data la donne.
  final String? color;
}

/// Période d'un mandat, en jours `AAAA-MM-JJ` inclus ; une borne `null` est
/// ouverte (depuis le début de la législature, ou toujours en cours).
typedef Period = ({String? start, String? end});

/// Appartenance à un groupe politique (organe) pendant une période.
typedef GroupSpell = ({String group, String? start, String? end});

bool _covers(String? start, String? end, String day) =>
    (start == null || start.compareTo(day) <= 0) &&
    (end == null || day.compareTo(end) <= 0);

/// Siège d'un député dans l'hémicycle (#71) et son historique, pour placer
/// chaque scrutin avec les députés et les groupes de son jour.
class DeputySeat {
  const DeputySeat({
    required this.place,
    this.terms = const [(start: null, end: null)],
    this.groups = const [],
  });

  /// Numéro du siège (`placeHemicycle`). Pour un député qui a quitté
  /// l'Assemblée, que l'archive ne place plus, le siège actuel de son
  /// successeur dans la même circonscription ; `null` sans successeur connu.
  /// Les votes nominatifs (`PlaceHistory`) donnent la place d'un jour donné.
  final int? place;

  /// Mandats de la 17e législature : de la prise de fonction
  /// (`datePriseFonction`) à la fin du mandat (`dateFin`).
  final List<Period> terms;

  /// Groupes politiques de la législature, avec leurs dates.
  final List<GroupSpell> groups;

  /// Siège-t-il le [day] (`AAAA-MM-JJ`) ?
  bool sitsOn(String day) => terms.any((t) => _covers(t.start, t.end, day));

  /// Premier jour du mandat en cours le [day], pour départager deux députés
  /// sur un même siège le jour d'une passation.
  String startOn(String day) =>
      terms.firstWhere((t) => _covers(t.start, t.end, day)).start ?? '';

  /// Groupe du député le [day], ou `null` s'il n'en a pas. Deux groupes le
  /// même jour (jour d'un changement de groupe) : le plus récent.
  String? groupOn(String day) {
    GroupSpell? best;
    for (final g in groups) {
      if (!_covers(g.start, g.end, day)) continue;
      if (best == null || (g.start ?? '').compareTo(best.start ?? '') >= 0) {
        best = g;
      }
    }
    return best?.group;
  }

  /// Groupes du député dans les [days] jours autour du [day] : plusieurs
  /// s'il a changé de groupe peu avant ou peu après.
  Set<String> groupsAround(String day, int days) {
    final d = DateTime.parse('${day}T00:00:00Z');
    String shift(int n) =>
        d.add(Duration(days: n)).toIso8601String().substring(0, 10);
    final (from, to) = (shift(-days), shift(days));
    return {
      for (final g in groups)
        if ((g.start == null || g.start!.compareTo(to) <= 0) &&
            (g.end == null || from.compareTo(g.end!) <= 0))
          g.group,
    };
  }

  /// Groupe actuel (sans date de fin), s'il en a un.
  String? get group {
    for (final g in groups) {
      if (g.end == null) return g.group;
    }
    return null;
  }

  List<Object?> toJson() => [
    place,
    [
      for (final t in terms) [t.start, t.end],
    ],
    [
      for (final g in groups) [g.group, g.start, g.end],
    ],
  ];

  static DeputySeat? fromJson(Object? json) {
    if (json case [
      final int? place,
      final List<Object?> terms,
      final List<Object?> groups,
    ]) {
      return DeputySeat(
        place: place,
        terms: [
          for (final t in terms)
            if (t case [final String? start, final String? end])
              (start: start, end: end),
        ],
        groups: [
          for (final g in groups)
            if (g case [
              final String group,
              final String? start,
              final String? end,
            ])
              (group: group, start: start, end: end),
        ],
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is DeputySeat && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;

  @override
  String toString() => 'DeputySeat${toJson()}';
}

/// Annuaire des groupes politiques (organes de type `GP`), pour donner un nom
/// lisible aux votes par groupe des scrutins, qui ne citent que la référence
/// de l'organe.
class GroupDirectory {
  GroupDirectory(
    Map<String, PoliticalGroup> groups, {
    Map<String, DeputySeat> seats = const {},
  }) : _groups = groups,
       seats = Map.unmodifiable(seats);

  final Map<String, PoliticalGroup> _groups;

  /// Siège et historique de chaque député de la législature, par référence
  /// d'acteur (`PA793432`) : les sièges de l'hémicycle « places réelles »
  /// (#71). Les députés partis ont le siège de leur successeur. Vide si
  /// l'archive ne donne aucun siège.
  final Map<String, DeputySeat> seats;

  /// Nombre de groupes connus.
  int get length => _groups.length;

  PoliticalGroup? operator [](String uid) => _groups[uid];

  /// Lit l'archive des acteurs et organes (`json/organe/<uid>.json`) et garde
  /// les groupes politiques. Un organe illisible est ignoré : il ne sert qu'à
  /// nommer un groupe, qui gardera sinon sa référence.
  ///
  /// Les acteurs (`json/acteur/<uid>.json`) donnent la place de chaque groupe
  /// dans l'hémicycle ([PoliticalGroup.place]) : un acteur illisible ou sans
  /// siège est ignoré.
  factory GroupDirectory.fromArchive(List<int> zipBytes) {
    final groups = <String, PoliticalGroup>{};
    final seats = <ActeurSeat>[];
    for (final file in ZipDecoder().decodeBytes(zipBytes)) {
      final name = file.name.toLowerCase();
      if (!file.isFile || !name.endsWith('.json')) continue;
      if (name.contains('organe/')) {
        if (parseOrganeJson(utf8.decode(file.content)) case final group?) {
          groups[group.uid] = group;
        }
      } else if (name.contains('acteur/')) {
        if (parseActeurSeat(utf8.decode(file.content)) case final seat?) {
          seats.add(seat);
        }
      }
    }
    if (groups.isEmpty) {
      throw const FormatException('Organes : aucun groupe politique trouvé');
    }
    final places = groupPlaces(seats.where((s) => s.inOffice));
    return GroupDirectory({
      for (final MapEntry(:key, :value) in groups.entries)
        key: PoliticalGroup(
          uid: value.uid,
          name: value.name,
          abbreviation: value.abbreviation,
          place: places[key],
          color: value.color,
        ),
    }, seats: deputySeats(seats));
  }

  /// Relit un annuaire enregistré par [toJson]. Lève [FormatException] s'il
  /// est illisible.
  factory GroupDirectory.fromJson(Object? json) {
    if (json is! Map<String, Object?> || json['version'] != _cacheVersion) {
      throw const FormatException('Annuaire des groupes : version inattendue');
    }
    final groups = json['groups'];
    final seats = json['seats'];
    if (groups is! Map<String, Object?> || seats is! Map<String, Object?>) {
      throw const FormatException('Annuaire des groupes : objet attendu');
    }
    return GroupDirectory(
      {
        for (final MapEntry(:key, :value) in groups.entries)
          if (value is Map<String, Object?> && value['name'] is String)
            key: PoliticalGroup(
              uid: key,
              name: value['name'] as String,
              abbreviation: value['abbreviation'] as String?,
              place: (value['place'] as num?)?.toDouble(),
              color: value['color'] as String?,
            ),
      },
      seats: {
        for (final MapEntry(:key, :value) in seats.entries)
          key: ?DeputySeat.fromJson(value),
      },
    );
  }

  /// Version 4 : historique des mandats et des groupes de chaque député,
  /// députés partis compris (version 3, #71 : place et groupe actuel). Un
  /// annuaire de version antérieure est illisible : il est reconstruit au
  /// passage suivant.
  static const _cacheVersion = 4;

  Map<String, Object?> toJson() => {
    'version': _cacheVersion,
    'groups': {
      for (final uid in _groups.keys.toList()..sort())
        uid: {
          'name': _groups[uid]!.name,
          'abbreviation': ?_groups[uid]!.abbreviation,
          'place': ?_groups[uid]!.place,
          'color': ?_groups[uid]!.color,
        },
    },
    'seats': {
      for (final acteur in seats.keys.toList()..sort())
        acteur: seats[acteur]!.toJson(),
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
    final color = organe['couleurAssociee'];
    return PoliticalGroup(
      uid: uid,
      name: name.trim(),
      abbreviation: abbreviation is String && abbreviation.trim().isNotEmpty
          ? abbreviation.trim()
          : null,
      color: color is String && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color)
          ? color.toUpperCase()
          : null,
    );
  } on Object {
    return null;
  }
}

/// Mandats et groupes d'un député de la 17e législature.
class ActeurSeat {
  const ActeurSeat({
    required this.seat,
    this.acteur,
    this.currentGroup,
    this.formerGroups = const {},
    this.terms = const [(start: null, end: null)],
    this.groups = const [],
    this.circonscription,
  });

  /// Référence de l'acteur (`PA793432`), si le JSON la donne.
  final String? acteur;

  /// Numéro du siège dans l'hémicycle (`placeHemicycle`) du mandat en cours ;
  /// `null` pour un député qui a quitté l'Assemblée.
  final int? seat;

  /// Groupe actuel (organe), s'il en a un.
  final String? currentGroup;

  /// Groupes quittés pendant la législature.
  final Set<String> formerGroups;

  /// Mandats de député, de la prise de fonction à la fin.
  final List<Period> terms;

  /// Groupes politiques, avec leurs dates.
  final List<GroupSpell> groups;

  /// Circonscription du dernier mandat (`refCirconscription`).
  final String? circonscription;

  /// Député en exercice, avec un siège.
  bool get inOffice => seat != null;
}

/// Lit le JSON d'un acteur ; renvoie ses mandats et ses groupes s'il a été
/// député de la 17e législature, sinon `null` (sénateur, ministre, JSON
/// illisible). Un député en exercice sans siège attribué est aussi écarté.
ActeurSeat? parseActeurSeat(String json) {
  try {
    final acteur = (jsonDecode(json) as Map<String, Object?>)['acteur'];
    if (acteur is! Map<String, Object?>) return null;
    final mandats = (acteur['mandats'] as Map<String, Object?>?)?['mandat'];
    int? seat;
    var inOffice = false;
    String? current;
    String? circonscription;
    String? lastStart;
    final former = <String>{};
    final terms = <Period>[];
    final groups = <GroupSpell>[];
    String? day(Object? v) =>
        v is String && v.length >= 10 ? v.substring(0, 10) : null;
    for (final m in mandats is List ? mandats : [mandats]) {
      if (m is! Map<String, Object?> || m['legislature'] != '17') continue;
      final ended = m['dateFin'] != null;
      switch (m['typeOrgane']) {
        case 'ASSEMBLEE':
          final mandature = m['mandature'];
          final start = day(
            mandature is Map<String, Object?>
                ? mandature['datePriseFonction'] ?? m['dateDebut']
                : m['dateDebut'],
          );
          terms.add((start: start, end: day(m['dateFin'])));
          if (!ended) {
            inOffice = true;
            if (mandature is Map<String, Object?>) {
              seat = int.tryParse('${mandature['placeHemicycle']}');
            }
          }
          final election = m['election'];
          if (election is Map<String, Object?> &&
              election['refCirconscription'] is String &&
              (start ?? '').compareTo(lastStart ?? '') >= 0) {
            circonscription = election['refCirconscription'] as String;
            lastStart = start;
          }
        case 'GP':
          final ref = (m['organes'] as Map<String, Object?>?)?['organeRef'];
          if (ref is! String) continue;
          groups.add((
            group: ref,
            start: day(m['dateDebut']),
            end: day(m['dateFin']),
          ));
          if (ended) {
            former.add(ref);
          } else {
            current = ref;
          }
      }
    }
    if (terms.isEmpty) return null;
    if (inOffice && (seat == null || seat <= 0)) return null;
    // `uid` est un objet `{"#text": "PA…"}` issu de la conversion XML → JSON.
    final uid = switch (acteur['uid']) {
      {'#text': final String text} => text,
      final String text => text,
      _ => null,
    };
    return ActeurSeat(
      seat: inOffice ? seat : null,
      acteur: uid,
      currentGroup: current,
      formerGroups: former..remove(current),
      terms: terms,
      groups: groups,
      circonscription: circonscription,
    );
  } on Object {
    return null;
  }
}

/// Sièges de l'hémicycle par député ([GroupDirectory.seats]) : le siège des
/// députés en exercice ; pour un député parti, que l'archive ne place plus,
/// le siège du député en exercice de sa circonscription (son suppléant ou
/// l'élu d'une partielle), qu'il occupait avant lui, ou `null` sans
/// successeur connu.
Map<String, DeputySeat> deputySeats(Iterable<ActeurSeat> acteurs) {
  final byCirco = <String, int>{
    for (final a in acteurs)
      if ((a.circonscription, a.seat) case (final circo?, final seat?))
        circo: seat,
  };
  return {
    for (final a in acteurs)
      ?a.acteur: DeputySeat(
        place: a.seat ?? byCirco[a.circonscription],
        terms: a.terms,
        groups: a.groups,
      ),
  };
}

/// Place moyenne de chaque groupe dans l'hémicycle (voir
/// [PoliticalGroup.place]) : sièges de ses membres actuels ; pour un groupe
/// sans membre actuel (dissous ou renommé), sièges actuels de ses anciens
/// membres.
Map<String, double> groupPlaces(Iterable<ActeurSeat> seats) {
  final current = <String, List<int>>{};
  final former = <String, List<int>>{};
  for (final s in seats) {
    final seat = s.seat;
    if (seat == null) continue;
    if (s.currentGroup case final g?) {
      current.putIfAbsent(g, () => []).add(seat);
    }
    for (final g in s.formerGroups) {
      former.putIfAbsent(g, () => []).add(seat);
    }
  }
  double mean(List<int> values) =>
      (values.reduce((a, b) => a + b) / values.length * 10).round() / 10;
  return {
    for (final g in {...current.keys, ...former.keys})
      g: mean(current[g] ?? former[g]!),
  };
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
