import 'dart:convert';

import 'package:vote_contract/vote_contract.dart';

import '../decision_details.dart' show detailCacheControl;
import '../dossier_index.dart';
import '../job.dart' show indexCacheControl;
import '../object_store.dart';
import 'llm_client.dart';
import 'source_text.dart';
import 'summary_cache.dart';
import 'summary_prompt.dart';
import 'text_source.dart';

/// Bornes d'un passage du résumeur : elles plafonnent le coût du modèle.
class SummaryLimits {
  const SummaryLimits({
    this.maxCallsPerPass = 15,
    this.maxRetriesPerPass = 5,
    this.maxFailures = 3,
    this.textWait = const Duration(days: 14),
  });

  /// Appels au modèle par passage, toutes décisions confondues. Au premier
  /// lancement, les 50 décisions de l'index sont résumées en 4 passages.
  final int maxCallsPerPass;

  /// Décisions « à régénérer » retentées par passage (texte relu, ou nouvel
  /// appel au modèle).
  final int maxRetriesPerPass;

  /// Échecs du modèle au-delà desquels une décision est abandonnée : elle
  /// garde son titre court officiel.
  final int maxFailures;

  /// Délai d'attente du texte d'une décision : passé ce délai après le vote,
  /// un texte toujours introuvable est résumé à partir de son intitulé.
  final Duration textWait;
}

/// Ce dont le résumeur a besoin : le modèle, la source des textes et ses
/// bornes. Absent (pas de clé `ANTHROPIC_API_KEY`), le job publie sans
/// nouveau résumé.
class SummaryService {
  const SummaryService({
    required this.llm,
    required this.texts,
    this.limits = const SummaryLimits(),
  });

  final LlmClient llm;
  final LegislativeTextSource texts;
  final SummaryLimits limits;
}

/// Bilan d'un passage du résumeur.
class SummaryReport {
  SummaryReport();

  /// Appels au modèle.
  int calls = 0;

  /// Décisions résumées à ce passage (appel ou reprise d'un résumé du même
  /// texte).
  final summarized = <String>[];

  /// Décisions résumées sans appel, à partir du résumé d'une autre décision
  /// sur le même texte.
  final reused = <String>[];

  /// Décisions « à régénérer », avec la raison.
  final pending = <String, String>{};

  /// Décisions abandonnées à ce passage.
  final abandoned = <String>[];

  /// Décisions laissées pour un passage suivant (plafond atteint).
  int deferred = 0;

  final warnings = <String>[];

  @override
  String toString() => [
    'Résumés : ${summarized.length} nouveaux (${reused.length} repris du '
        'même texte), $calls appels au modèle, ${pending.length} à '
        'régénérer, $deferred reportés (plafond du passage).',
    for (final MapEntry(:key, :value) in pending.entries)
      '  à régénérer $key : $value',
    for (final id in abandoned) '  abandonné $id',
    ...warnings.map((w) => 'Attention : $w'),
  ].join('\n');
}

/// Types de décision qui portent sur un texte : leur résumé s'appuie sur le
/// texte déposé. Les autres (motion de censure, déclaration du
/// Gouvernement, scrutin non reconnu) sont résumés à partir de l'intitulé.
const textDecisionTypes = {
  DecisionType.ensembleTexte,
  DecisionType.resolution,
  DecisionType.rejetPrealable,
  DecisionType.premierePartieBudget,
};

/// Un passage du résumeur, sur l'index publié ([indexPath]) :
///
/// 1. chaque décision sans résumé, de la plus récente à la plus ancienne,
///    reçoit son texte source : exposé des motifs du texte déposé, sinon ses
///    articles, sinon l'intitulé (types sans texte, ou texte introuvable
///    après [SummaryLimits.textWait]) ;
/// 2. un texte pas encore en ligne, une décision provisoire pas encore
///    rattachée à son dossier, ou un échec du modèle marquent la décision
///    « à régénérer » : elle reste publiée avec son titre court officiel ;
/// 3. un seul appel par décision : une décision résumée ne l'est plus
///    jamais ([SummaryCache]) ; une décision sur un texte déjà résumé
///    reprend ce résumé sans appel ;
/// 4. au plus [SummaryLimits.maxCallsPerPass] appels et
///    [SummaryLimits.maxRetriesPerPass] décisions « à régénérer » retentées
///    par passage.
///
/// Les résumés obtenus sont écrits dans le cache, puis dans les fichiers de
/// détail et l'index publiés.
Future<SummaryReport> runSummaryPass({
  required ObjectStore store,
  required SummaryService service,
  DossierIndex? dossiers,
  DateTime Function() clock = DateTime.now,
}) async {
  final report = SummaryReport();
  final now = clock().toUtc();
  final index = await _readIndex(store, report.warnings);
  if (index == null) return report;
  final cache = await SummaryCache.read(store, report.warnings);
  var cacheChanged = cache.adoptPublished(index, now: now);
  final limits = service.limits;

  final texts = <String, Future<TextFetch>>{};
  var retries = 0;
  for (final d in index.decisions) {
    final entry = cache[d.id];
    if (entry != null && entry.status != SummaryStatus.aRegenerer) continue;
    final isRetry = entry != null;
    if (report.calls >= limits.maxCallsPerPass ||
        (isRetry && retries >= limits.maxRetriesPerPass)) {
      report.deferred++;
      continue;
    }
    if (isRetry) retries++;
    cacheChanged = true;

    final plan = await _plan(
      d,
      cache: cache,
      dossiers: dossiers,
      fetch: (uid) => texts[uid] ??= service.texts.fetch(uid),
      now: now,
      textWait: limits.textWait,
    );
    switch (plan) {
      case _Wait(:final reason):
        cache[d.id] = SummaryEntry(
          status: SummaryStatus.aRegenerer,
          updatedAt: now,
          reason: reason,
          failures: entry?.failures ?? 0,
        );
        report.pending[d.id] = reason;
      case _Reuse(:final from, :final textUid):
        cache[d.id] = SummaryEntry(
          status: SummaryStatus.resume,
          updatedAt: now,
          summary: from.summary,
          source: from.source,
          textUid: textUid,
          reason: 'repris du résumé du même texte',
        );
        report.summarized.add(d.id);
        report.reused.add(d.id);
      case _Call(:final source, :final textUid):
        report.calls++;
        try {
          final response = await service.llm.createMessage(
            buildSummaryRequest(decision: d, source: source),
          );
          final summary = parseSummaryResponse(
            response,
            withPoints: source != null,
          );
          cache[d.id] = SummaryEntry(
            status: SummaryStatus.resume,
            updatedAt: now,
            summary: summary,
            source: source?.kind ?? SourceKind.titre,
            textUid: textUid,
            model: response['model'] is String
                ? response['model'] as String
                : summaryModel,
          );
          report.summarized.add(d.id);
        } on LlmException catch (e) {
          final failures = (entry?.failures ?? 0) + 1;
          final abandon = failures >= limits.maxFailures;
          cache[d.id] = SummaryEntry(
            status: abandon
                ? SummaryStatus.abandonne
                : SummaryStatus.aRegenerer,
            updatedAt: now,
            textUid: textUid,
            reason: '$e',
            failures: failures,
          );
          if (abandon) {
            report.abandoned.add(d.id);
          } else {
            report.pending[d.id] = 'échec du modèle ($e)';
          }
        }
    }
  }

  if (cacheChanged) await cache.write(store);
  if (report.summarized.isNotEmpty) {
    await _publish(store, index, cache, report.summarized, now);
  }
  return report;
}

sealed class _Plan {
  const _Plan();
}

/// Pas encore : la décision est « à régénérer ».
class _Wait extends _Plan {
  const _Wait(this.reason);

  final String reason;
}

/// Le texte est déjà résumé pour une autre décision.
class _Reuse extends _Plan {
  const _Reuse(this.from, this.textUid);

  final SummaryEntry from;
  final String textUid;
}

/// Appel au modèle ; [source] `null` : intitulé seul.
class _Call extends _Plan {
  const _Call({this.source, this.textUid});

  final SourceText? source;
  final String? textUid;
}

Future<_Plan> _plan(
  DecisionSummary d, {
  required SummaryCache cache,
  required DossierIndex? dossiers,
  required Future<TextFetch> Function(String uid) fetch,
  required DateTime now,
  required Duration textWait,
}) async {
  if (!textDecisionTypes.contains(d.type)) return const _Call();
  final dossierUid = dossierUidFromUrl(d.dossierUrl);
  final textUid = dossierUid == null ? null : dossiers?.depositText(dossierUid);
  if (textUid == null) {
    // Une décision provisoire est souvent rattachée à son dossier à la
    // confirmation : on attend plutôt que de la résumer sur son intitulé.
    if (d.status == DecisionStatus.provisoire) {
      return const _Wait('dossier pas encore rattaché (décision provisoire)');
    }
    return const _Call();
  }
  for (final MapEntry(value: e) in cache.entries) {
    if (e.status == SummaryStatus.resume &&
        e.textUid == textUid &&
        e.source != null &&
        e.source != SourceKind.titre &&
        e.summary?.promptVersion == summaryPromptVersion) {
      return _Reuse(e, textUid);
    }
  }
  final String reason;
  switch (await fetch(textUid)) {
    case TextFound(:final html):
      if (extractSourceText(html) case final source?) {
        return _Call(source: source, textUid: textUid);
      }
      reason = 'ni exposé des motifs ni articles';
    case TextUnavailable(reason: final why):
      reason = why;
  }
  if (now.difference(d.date) < textWait) {
    return _Wait('texte $textUid indisponible ($reason)');
  }
  return _Call(textUid: textUid);
}

Future<DecisionIndex?> _readIndex(
  ObjectStore store,
  List<String> warnings,
) async {
  final raw = await store.read(indexPath);
  if (raw == null) return null;
  try {
    return DecisionIndex.fromJson(jsonDecode(raw));
  } on Object catch (e) {
    warnings.add('index publié illisible, résumés reportés ($e)');
    return null;
  }
}

/// Écrit les résumés de [ids] dans leurs fichiers de détail, puis l'index.
Future<void> _publish(
  ObjectStore store,
  DecisionIndex index,
  SummaryCache cache,
  List<String> ids,
  DateTime now,
) async {
  for (final id in ids) {
    final key = decisionDetailPath(id);
    final raw = await store.read(key);
    if (raw == null) continue;
    final DecisionDetail detail;
    try {
      detail = DecisionDetail.fromJson(jsonDecode(raw));
    } on Object {
      continue;
    }
    final body = const JsonEncoder.withIndent(
      '  ',
    ).convert(detail.withDecision(cache.apply(detail.decision)).toJson());
    if (body != raw) {
      await store.write(key, body, cacheControl: detailCacheControl);
    }
  }
  final updated = cache.applyTo(index);
  await store.write(
    indexPath,
    const JsonEncoder.withIndent('  ').convert(
      DecisionIndex(
        generatedAt: now,
        source: updated.source,
        decisions: updated.decisions,
        upcoming: updated.upcoming,
      ).toJson(),
    ),
    cacheControl: indexCacheControl,
  );
}
