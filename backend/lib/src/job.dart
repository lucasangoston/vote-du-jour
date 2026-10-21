import 'dart:convert';

import 'package:vote_contract/vote_contract.dart';

import 'agenda/in_debate.dart';
import 'arguments/arguments_state.dart';
import 'decision_details.dart';
import 'dossier_index.dart';
import 'dump_reader.dart';
import 'dump_source.dart';
import 'group_directory.dart';
import 'index_builder.dart';
import 'live/live_state.dart';
import 'live/reconciler.dart';
import 'object_store.dart';
import 'scrutin.dart';
import 'summary/summarizer.dart';
import 'summary/summary_cache.dart';

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
  const JobSkipped({this.warnings = const [], this.summaries});

  /// Problèmes non bloquants (jeu de données des dossiers indisponible…).
  final List<String> warnings;

  /// Bilan du résumeur ; `null` sans clé d'API.
  final SummaryReport? summaries;

  @override
  String toString() => [
    'Jeux de données inchangés : rien à retraiter.',
    ...warnings.map((w) => 'Attention : $w'),
    _summaryLine(summaries),
  ].join('\n');
}

String _summaryLine(SummaryReport? summaries) =>
    summaries?.toString() ??
    'Résumés désactivés (pas de clé ANTHROPIC_API_KEY) : résumés existants '
        'conservés.';

/// Un nouvel index a été publié.
class JobPublished extends JobOutcome {
  const JobPublished({
    required this.scrutins,
    required this.index,
    required this.unrecognized,
    this.warnings = const [],
    this.detailsWritten = 0,
    this.summaries,
  });

  /// Bilan du résumeur ; `null` sans clé d'API.
  final SummaryReport? summaries;

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
    _summaryLine(summaries),
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
/// Les scrutins provisoires de la détection en direct ([LiveState]) passent
/// par le réconciliateur ([reconcile]) : ceux que le jeu de données contient
/// sont confirmés, les autres restent publiés comme provisoires. Le job
/// enregistre aussi l'instantané des scrutins dont la détection en direct a
/// besoin ([ConfirmedSnapshot]) et les votes sur les articles du bloc « En
/// débat » ([ArticleVotesState], #55) ; s'il en manque un, le jeu de données
/// est retraité.
///
/// Les résumés déjà obtenus ([SummaryCache]) sont appliqués à chaque index
/// publié. Puis, avec [summaries] (clé d'API présente), qu'un jeu de données
/// ait changé ou non, un passage du résumeur ([runSummaryPass]) résume les
/// nouvelles décisions et retente celles « à régénérer ».
///
/// [force] ignore l'état et retraite les jeux de données (sans régénérer
/// les résumés).
Future<JobOutcome> runJob({
  required DumpSource source,
  required ObjectStore store,
  DumpSource? dossiers,
  DumpSource? organes,
  SummaryService? summaries,
  DateTime Function() clock = DateTime.now,
  bool force = false,
}) async {
  final warnings = <String>[];
  // Sans instantané pour la détection en direct (#10) ou sans votes sur
  // les articles (#55), on retraite le jeu de données pour les écrire.
  final previous =
      force ||
          await store.read(confirmedSnapshotKey) == null ||
          await store.read(articleVotesKey) == null
      ? null
      : _readLastModified(await store.read(stateKey));

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
  Future<SummaryReport?> summarize() async => summaries == null
      ? null
      : await runSummaryPass(
          store: store,
          service: summaries,
          dossiers: dossierIndex,
          clock: clock,
        );
  switch (fetch) {
    case DumpNotModified():
      return JobSkipped(warnings: warnings, summaries: await summarize());
    case DumpDownloaded(:final bytes, :final lastModified):
      final scrutins = readScrutinsArchive(bytes);
      final now = clock().toUtc();
      // Les décisions provisoires détectées en direct (#10) que le jeu de
      // données ne contient pas encore restent publiées.
      final live = await LiveState.read(store, warnings);
      final reconciled = reconcile(
        confirmed: scrutins,
        provisional: live.provisionalScrutins,
        generatedAt: now,
        dossiers: dossierIndex,
      );
      // Les décisions déjà résumées gardent leur résumé ; un cache perdu
      // les reprend de l'index encore publié.
      final summaryCache = await SummaryCache.read(store, warnings);
      final published = await _readPublishedIndex(store);
      if (summaryCache.adoptPublished(published, now: now)) {
        await summaryCache.write(store);
      }
      // L'ordre du jour (#52) et le texte en débat (#55) publiés sont
      // gardés : le passage de l'agenda, juste après le job, les met à jour.
      final index = summaryCache
          .applyTo(reconciled.index)
          .withUpcoming(published?.upcoming)
          .withInDebate(published?.inDebate);
      // Les détails avant l'index, qui renvoie vers eux. Les décisions
      // encore provisoires ont le décompte du site, sans vote par groupe.
      // Les décisions déjà argumentées (#35) gardent leurs arguments.
      final arguments = await ArgumentsState.read(store, warnings);
      final detailsWritten = await publishDecisionDetails(
        store,
        buildDecisionDetails(
          [...scrutins, ...reconciled.pending],
          index,
          groups: groups.directory,
        ).map(arguments.apply),
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
      await ConfirmedSnapshot.fromDump(
        scrutins,
        lastModified: lastModified,
      ).write(store);
      await ArticleVotesState.fromDump(scrutins, now: now).write(store);
      await live
          .keepOnly({for (final s in reconciled.pending) s.uid})
          .write(store);
      return JobPublished(
        scrutins: scrutins.length,
        index: index,
        unrecognized: unrecognizedScrutins(scrutins),
        warnings: warnings,
        detailsWritten: detailsWritten,
        summaries: await summarize(),
      );
  }
}

/// Index publié, ou `null` s'il est absent ou illisible.
Future<DecisionIndex?> _readPublishedIndex(ObjectStore store) async {
  final raw = await store.read(indexPath);
  if (raw == null) return null;
  try {
    return DecisionIndex.fromJson(jsonDecode(raw));
  } on Object {
    return null;
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
