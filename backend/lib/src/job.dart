import 'dart:convert';

import 'package:vote_contract/vote_contract.dart';

import 'decision_details.dart';
import 'dossier_index.dart';
import 'dump_reader.dart';
import 'dump_source.dart';
import 'group_directory.dart';
import 'index_builder.dart';
import 'object_store.dart';
import 'scrutin.dart';

/// Clé de l'état du job dans le bucket : le `Last-Modified` du dernier jeu de
/// données traité.
const stateKey = 'state/scrutins-dump.json';

/// Clé de l'état des dossiers législatifs : le `Last-Modified` du dernier jeu
/// de données traité et l'index qui en a été tiré, réutilisé tant que le jeu
/// de données ne change pas.
const dossiersStateKey = 'state/dossiers.json';

/// Cache HTTP de l'index : court, le job tourne toutes les heures.
const indexCacheControl = 'public, max-age=300';

/// Issue d'une exécution du job.
sealed class JobOutcome {
  const JobOutcome();
}

/// Les jeux de données n'ont pas changé : rien n'a été retraité ni republié.
class JobSkipped extends JobOutcome {
  const JobSkipped({this.warnings = const []});

  /// Problèmes non bloquants (jeu de données des dossiers indisponible…).
  final List<String> warnings;

  @override
  String toString() => [
    'Jeux de données inchangés : rien à publier.',
    ...warnings.map((w) => 'Attention : $w'),
  ].join('\n');
}

/// Un nouvel index a été publié.
class JobPublished extends JobOutcome {
  const JobPublished({
    required this.scrutins,
    required this.index,
    required this.unrecognized,
    this.warnings = const [],
    this.detailsWritten = 0,
  });

  /// Nombre de scrutins lus dans le jeu de données.
  final int scrutins;
  final DecisionIndex index;

  /// Scrutins écartés faute de règle reconnaissant leur intitulé, à relire.
  final List<Scrutin> unrecognized;

  /// Problèmes non bloquants (jeu de données des dossiers indisponible…).
  final List<String> warnings;

  /// Fichiers de détail réécrits (les autres n'avaient pas changé).
  final int detailsWritten;

  @override
  String toString() => [
    '$scrutins scrutins lus, ${index.decisions.length} décisions publiées '
        'dans $indexPath '
        '(${index.decisions.where((d) => d.dossierUrl != null).length} '
        'rattachées à un dossier, '
        '${index.decisions.where((d) => d.voteMode == VoteMode.mainLevee).length}'
        ' adoptées à main levée).',
    '$detailsWritten fichiers de détail réécrits '
        '(${decisionDetailPath('<id>')}).',
    ...warnings.map((w) => 'Attention : $w'),
    if (unrecognized.isNotEmpty)
      '${unrecognized.length} intitulés non reconnus, écartés (à relire) :',
    for (final s in unrecognized)
      '  ${s.numero} (${s.codeTypeVote}) ${s.titre}',
  ].join('\n');
}

/// Exécute le job : récupère les jeux de données des scrutins et des dossiers
/// législatifs s'ils ont changé depuis la dernière exécution, publie l'index
/// des dernières décisions, puis enregistre l'état. L'état n'est écrit
/// qu'après la publication : en cas d'échec, la prochaine exécution retraite
/// les mêmes jeux de données.
///
/// Les dossiers ([dossiers]) donnent le titre court et l'étape. Leur index
/// est gardé dans l'état : quand seuls les scrutins changent, il est relu
/// sans retélécharger les dossiers ; quand les dossiers changent, les
/// scrutins sont retraités même s'ils n'ont pas changé. Si les dossiers sont
/// indisponibles ou illisibles, le job publie quand même, avec le dernier
/// index connu ou, à défaut, des libellés tirés des intitulés.
///
/// [force] ignore l'état et retraite les jeux de données.
Future<JobOutcome> runJob({
  required DumpSource source,
  required ObjectStore store,
  DumpSource? dossiers,
  DumpSource? organes,
  DateTime Function() clock = DateTime.now,
  bool force = false,
}) async {
  final warnings = <String>[];
  final previous = force ? null : _readLastModified(await store.read(stateKey));

  final dossierState = dossiers == null || force
      ? null
      : await _readDossierState(store, warnings);
  final dossierUpdate = dossiers == null
      ? null
      : await _fetchDossiers(dossiers, dossierState, warnings);
  final dossierIndex = dossierUpdate?.index ?? dossierState?.index;
  // Noms des groupes politiques, pour les fichiers de détail.
  final groups = await loadGroupDirectory(
    source: organes,
    store: store,
    warnings: warnings,
    now: clock(),
    force: force,
  );

  final fetch = await source.fetch(
    // De nouveaux dossiers changent les libellés, de nouveaux noms de groupes
    // les fichiers de détail : on retraite les scrutins.
    ifModifiedSince: dossierUpdate != null || groups.changed ? null : previous,
  );
  switch (fetch) {
    case DumpNotModified():
      return JobSkipped(warnings: warnings);
    case DumpDownloaded(:final bytes, :final lastModified):
      final scrutins = readScrutinsArchive(bytes);
      final now = clock().toUtc();
      final index = buildDecisionIndex(
        scrutins,
        generatedAt: now,
        dossiers: dossierIndex,
      );
      // Les détails avant l'index, qui renvoie vers eux.
      final detailsWritten = await publishDecisionDetails(
        store,
        buildDecisionDetails(scrutins, index, groups: groups.directory),
      );
      await store.write(
        indexPath,
        const JsonEncoder.withIndent('  ').convert(index.toJson()),
        cacheControl: indexCacheControl,
      );
      await store.write(
        stateKey,
        jsonEncode({
          'lastModified': lastModified,
          'processedAt': now.toIso8601String(),
        }),
        cacheControl: 'no-store',
      );
      if (dossierUpdate != null) {
        await store.write(
          dossiersStateKey,
          jsonEncode({
            'lastModified': dossierUpdate.lastModified,
            'processedAt': now.toIso8601String(),
            'index': dossierUpdate.index.toJson(),
          }),
          cacheControl: 'no-store',
        );
      }
      await groups.save(store);
      return JobPublished(
        scrutins: scrutins.length,
        index: index,
        unrecognized: unrecognizedScrutins(scrutins),
        warnings: warnings,
        detailsWritten: detailsWritten,
      );
  }
}

/// Index des dossiers et `Last-Modified` du jeu de données dont il est tiré.
typedef _DossierState = ({String? lastModified, DossierIndex index});

Future<_DossierState?> _readDossierState(
  ObjectStore store,
  List<String> warnings,
) async {
  final raw = await store.read(dossiersStateKey);
  if (raw == null) return null;
  try {
    final json = jsonDecode(raw) as Map<String, Object?>;
    return (
      lastModified: json['lastModified'] as String?,
      index: DossierIndex.fromJson(json['index']),
    );
  } on Object catch (e) {
    warnings.add('état des dossiers illisible, il sera reconstruit ($e)');
    return null;
  }
}

/// Télécharge et lit les dossiers s'ils ont changé depuis [state] ; `null`
/// s'ils n'ont pas changé ou sont indisponibles (avertissement ajouté à
/// [warnings]).
Future<_DossierState?> _fetchDossiers(
  DumpSource source,
  _DossierState? state,
  List<String> warnings,
) async {
  try {
    // Sans index en cache, il faut les données même si elles n'ont pas
    // changé.
    final fetch = await source.fetch(ifModifiedSince: state?.lastModified);
    return switch (fetch) {
      DumpNotModified() => null,
      DumpDownloaded(:final bytes, :final lastModified) => (
        lastModified: lastModified,
        index: DossierIndex.fromArchive(bytes),
      ),
    };
  } on Exception catch (e) {
    final fallback = state != null
        ? 'dernier index connu utilisé'
        : 'libellés tirés des intitulés';
    warnings.add('dossiers législatifs indisponibles, $fallback ($e)');
    return null;
  }
}

String? _readLastModified(String? state) {
  if (state == null) return null;
  try {
    final json = jsonDecode(state);
    return json is Map && json['lastModified'] is String
        ? json['lastModified'] as String
        : null;
  } on FormatException {
    return null;
  }
}
