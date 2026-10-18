import 'dart:convert';

import 'package:vote_contract/vote_contract.dart';

import '../object_store.dart';

/// Clé de l'état des arguments dans le bucket.
const argumentsStateKey = 'state/arguments.json';

/// État des arguments d'une décision.
enum ArgumentsStatus {
  /// Le modèle a répondu avec cette version de la consigne : arguments
  /// publiés (ou aucun, si les interventions n'en contenaient pas). Plus
  /// jamais redemandés pour cette version.
  fait('fait'),

  /// Rattachée à ses explications de vote, en attente d'un appel (plafond
  /// du passage atteint, ou échec du modèle à retenter).
  enAttente('en_attente'),

  /// Trop d'échecs du modèle : plus retentée, sans arguments.
  abandonne('abandonne');

  const ArgumentsStatus(this.json);

  final String json;

  static ArgumentsStatus? tryParse(Object? value) =>
      ArgumentsStatus.values.where((s) => s.json == value).firstOrNull;
}

/// Ligne de l'état pour une décision.
class ArgumentsEntry {
  const ArgumentsEntry({
    required this.status,
    required this.updatedAt,
    this.promptVersion,
    this.compteRendu,
    this.arguments,
    this.model,
    this.reason,
    this.failures = 0,
  });

  final ArgumentsStatus status;
  final DateTime updatedAt;

  /// Version de la consigne de la réponse ([ArgumentsStatus.fait]).
  final int? promptVersion;

  /// Compte rendu rattaché (`CRSANR5L17S2027O1N020`).
  final String? compteRendu;

  /// Arguments publiés ; `null` si le modèle n'en a trouvé aucun.
  final DecisionArguments? arguments;

  /// Modèle qui a rédigé les arguments.
  final String? model;

  /// Raison du dernier échec, ou de l'attente.
  final String? reason;

  /// Échecs du modèle (réponse rejetée, refus, erreur HTTP).
  final int failures;

  static ArgumentsEntry? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final status = ArgumentsStatus.tryParse(json['status']);
    final updatedAt = DateTime.tryParse('${json['updatedAt']}');
    if (status == null || updatedAt == null) return null;
    String? string(String key) =>
        json[key] is String ? json[key] as String : null;
    final promptVersion = json['promptVersion'];
    final failures = json['failures'];
    return ArgumentsEntry(
      status: status,
      updatedAt: updatedAt,
      promptVersion: promptVersion is int ? promptVersion : null,
      compteRendu: string('compteRendu'),
      arguments: DecisionArguments.tryFromJson(json['arguments']),
      model: string('model'),
      reason: string('reason'),
      failures: failures is int ? failures : 0,
    );
  }

  Map<String, Object?> toJson() => {
    'status': status.json,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'promptVersion': ?promptVersion,
    'compteRendu': ?compteRendu,
    'arguments': ?arguments?.toJson(),
    'model': ?model,
    'reason': ?reason,
    if (failures > 0) 'failures': failures,
  };
}

/// État des arguments (`state/arguments.json`) : `Last-Modified` de la
/// dernière archive des comptes rendus lue, et une ligne par décision
/// rattachée. Une décision faite pour la version courante de la consigne
/// n'est plus jamais envoyée au modèle.
///
/// Le job l'applique aux fichiers de détail qu'il reconstruit ([apply]) :
/// une décision republiée garde ses arguments.
class ArgumentsState {
  ArgumentsState({this.lastModified, Map<String, ArgumentsEntry>? entries})
    : _entries = entries ?? {};

  /// `Last-Modified` de la dernière archive lue, pour `If-Modified-Since`.
  String? lastModified;

  final Map<String, ArgumentsEntry> _entries;

  static const _version = 1;

  ArgumentsEntry? operator [](String id) => _entries[id];

  void operator []=(String id, ArgumentsEntry entry) => _entries[id] = entry;

  void remove(String id) => _entries.remove(id);

  Iterable<MapEntry<String, ArgumentsEntry>> get entries => _entries.entries;

  /// Lit l'état ; vide s'il n'existe pas. Un état illisible est signalé dans
  /// [warnings] et vaut état vide (les arguments seront redemandés, dans la
  /// limite du plafond).
  static Future<ArgumentsState> read(
    ObjectStore store,
    List<String> warnings,
  ) async {
    final raw = await store.read(argumentsStateKey);
    if (raw == null) return ArgumentsState();
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?> || json['version'] != _version) {
        throw const FormatException('version inattendue');
      }
      final entries = json['entries'] as Map<String, Object?>;
      return ArgumentsState(
        lastModified: json['lastModified'] as String?,
        entries: {
          for (final MapEntry(:key, :value) in entries.entries)
            key: ?ArgumentsEntry.tryFromJson(value),
        },
      );
    } on Object catch (e) {
      warnings.add("état des arguments illisible, il sera reconstruit ($e)");
      return ArgumentsState();
    }
  }

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'version': _version,
    'lastModified': ?lastModified,
    'entries': {
      for (final id in _entries.keys.toList()..sort())
        id: _entries[id]!.toJson(),
    },
  });

  Future<void> write(ObjectStore store) =>
      store.write(argumentsStateKey, encode(), cacheControl: 'no-store');

  /// Arguments publiés de la décision [id], s'il y en a.
  DecisionArguments? argumentsOf(String id) => switch (_entries[id]) {
    ArgumentsEntry(status: ArgumentsStatus.fait, :final arguments) => arguments,
    _ => null,
  };

  /// [detail] avec ses arguments, s'il en a.
  DecisionDetail apply(DecisionDetail detail) =>
      switch (argumentsOf(detail.decision.id)) {
        final arguments? => detail.withArguments(arguments),
        null => detail,
      };
}
