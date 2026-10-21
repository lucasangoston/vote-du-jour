import 'dart:convert';

import 'package:vote_contract/vote_contract.dart';

import '../object_store.dart';
import 'source_text.dart';

/// Clé du cache des résumés dans le bucket.
const summaryCacheKey = 'state/resumes.json';

/// État du résumé d'une décision.
enum SummaryStatus {
  /// Résumée : le résumé est publié et ne sera plus jamais redemandé.
  resume('resume'),

  /// « À régénérer » : texte pas encore en ligne, ou échec du modèle. La
  /// décision est publiée avec son titre court officiel et retentée à un
  /// passage suivant.
  aRegenerer('a_regenerer'),

  /// Trop d'échecs du modèle : plus retentée, la décision garde son titre
  /// court officiel.
  abandonne('abandonne');

  const SummaryStatus(this.json);

  final String json;

  static SummaryStatus? tryParse(Object? value) =>
      SummaryStatus.values.where((s) => s.json == value).firstOrNull;
}

/// Ligne du cache pour une décision.
class SummaryEntry {
  const SummaryEntry({
    required this.status,
    required this.updatedAt,
    this.summary,
    this.source,
    this.textUid,
    this.model,
    this.reason,
    this.failures = 0,
  });

  final SummaryStatus status;
  final DateTime updatedAt;

  /// Résumé publié ([SummaryStatus.resume]), points compris.
  final PlainSummary? summary;

  /// Source du résumé.
  final SourceKind? source;

  /// Texte résumé (`PIONANR5L17B0284`), s'il y en a un.
  final String? textUid;

  /// Modèle qui a rédigé le résumé ; `null` s'il a été repris d'une autre
  /// décision ou de l'index publié.
  final String? model;

  /// Raison du dernier échec (« à régénérer », abandon).
  final String? reason;

  /// Échecs du modèle (réponse invalide, refus, erreur HTTP). Un texte pas
  /// encore en ligne n'en est pas un.
  final int failures;

  static SummaryEntry? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final status = SummaryStatus.tryParse(json['status']);
    final updatedAt = DateTime.tryParse('${json['updatedAt']}');
    if (status == null || updatedAt == null) return null;
    final summary = PlainSummary.tryFromJson(json['summary']);
    if (status == SummaryStatus.resume && summary == null) return null;
    final failures = json['failures'];
    String? string(String key) =>
        json[key] is String ? json[key] as String : null;
    return SummaryEntry(
      status: status,
      updatedAt: updatedAt,
      summary: summary,
      source: SourceKind.tryParse(json['source']),
      textUid: string('textUid'),
      model: string('model'),
      reason: string('reason'),
      failures: failures is int ? failures : 0,
    );
  }

  Map<String, Object?> toJson() => {
    'status': status.json,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'summary': ?summary?.toJson(),
    'source': ?source?.json,
    'textUid': ?textUid,
    'model': ?model,
    'reason': ?reason,
    if (failures > 0) 'failures': failures,
  };
}

/// Cache des résumés (`state/resumes.json`), par identifiant de décision : un
/// seul appel au modèle par décision, quels que soient les passages et les
/// republications de l'index.
///
/// Le job (et la détection en direct, en lecture seule) l'applique à chaque
/// index qu'il publie : une décision republiée garde son résumé.
class SummaryCache {
  SummaryCache([Map<String, SummaryEntry>? entries]) : _entries = entries ?? {};

  final Map<String, SummaryEntry> _entries;

  static const _version = 1;

  SummaryEntry? operator [](String id) => _entries[id];

  void operator []=(String id, SummaryEntry entry) => _entries[id] = entry;

  Iterable<MapEntry<String, SummaryEntry>> get entries => _entries.entries;

  /// Lit le cache ; vide s'il n'existe pas. Un cache illisible est signalé
  /// dans [warnings] et vaut cache vide : les résumés déjà publiés sont
  /// repris de l'index ([adoptPublished]), sans nouvel appel.
  static Future<SummaryCache> read(
    ObjectStore store,
    List<String> warnings,
  ) async {
    final raw = await store.read(summaryCacheKey);
    if (raw == null) return SummaryCache();
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?> || json['version'] != _version) {
        throw const FormatException('version inattendue');
      }
      final entries = json['entries'] as Map<String, Object?>;
      return SummaryCache({
        for (final MapEntry(:key, :value) in entries.entries)
          key: ?SummaryEntry.tryFromJson(value),
      });
    } on Object catch (e) {
      warnings.add(
        'cache des résumés illisible, repris de l\'index publié ($e)',
      );
      return SummaryCache();
    }
  }

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'version': _version,
    'entries': {
      for (final id in _entries.keys.toList()..sort())
        id: _entries[id]!.toJson(),
    },
  });

  Future<void> write(ObjectStore store) =>
      store.write(summaryCacheKey, encode(), cacheControl: 'no-store');

  /// Résumé publié de la décision [id], s'il y en a un.
  PlainSummary? summaryOf(String id) => switch (_entries[id]) {
    SummaryEntry(status: SummaryStatus.resume, :final summary) => summary,
    _ => null,
  };

  /// [decision] avec son résumé, s'il y en a un.
  DecisionSummary apply(DecisionSummary decision) =>
      switch (summaryOf(decision.id)) {
        final summary? => decision.withSummary(summary),
        null => decision,
      };

  /// [index] avec le résumé de chaque décision résumée.
  DecisionIndex applyTo(DecisionIndex index) => DecisionIndex(
    generatedAt: index.generatedAt,
    source: index.source,
    decisions: [for (final d in index.decisions) apply(d)],
    upcoming: index.upcoming,
  );

  /// Reprend les résumés de l'index publié [published] absents du cache
  /// (cache perdu ou illisible) : ils ne sont pas redemandés. Les points ne
  /// figurent pas dans l'index : ils sont repris des fichiers de détail
  /// quand le job les republie. Renvoie `true` si le cache a changé.
  bool adoptPublished(DecisionIndex? published, {required DateTime now}) {
    var changed = false;
    for (final d in published?.decisions ?? const <DecisionSummary>[]) {
      final summary = d.summary;
      if (summary == null || summaryOf(d.id) != null) continue;
      _entries[d.id] = SummaryEntry(
        status: SummaryStatus.resume,
        updatedAt: now,
        summary: summary,
        reason: "repris de l'index publié",
      );
      changed = true;
    }
    return changed;
  }
}
