import 'package:vote_contract/vote_contract.dart';

import '../vote_mode_label.dart';

/// Instantané des dernières décisions, écrit par l'app dans l'espace partagé
/// avec les widgets natifs (App Group sur iOS, SharedPreferences sur Android).
///
/// Les widgets ne connaissent que ce format, pas le contrat publié : l'app
/// décide ici de ce qu'il faut afficher (titre, étape, phrase d'explication),
/// les widgets se contentent du rendu. Un champ optionnel absent n'est pas
/// affiché ; ajouter un champ optionnel ne change pas [version].
///
/// ```json
/// {
///   "version": 1,
///   "savedAt": "2026-10-17T10:17:00.000Z",
///   "decisions": [
///     {
///       "id": "VTANR5L17V8706",
///       "result": "adopte",
///       "date": "2026-10-13",
///       "title": "L'ensemble du projet de loi …",
///       "stage": "1re lecture à l'AN",
///       "explanation": "Le texte prévoit …"
///     }
///   ]
/// }
/// ```
class WidgetSnapshot {
  const WidgetSnapshot({required this.savedAt, required this.decisions});

  /// Construit l'instantané à partir de l'index publié : les [maxDecisions]
  /// plus récentes (le grand widget en affichera trois).
  factory WidgetSnapshot.fromIndex(
    DecisionIndex index, {
    required DateTime savedAt,
    int maxDecisions = 3,
  }) {
    return WidgetSnapshot(
      savedAt: savedAt,
      decisions: [
        for (final d in index.decisions.take(maxDecisions))
          WidgetDecision.fromSummary(d),
      ],
    );
  }

  /// Version du format lu par les widgets natifs. Un changement cassant
  /// l'incrémente ; les widgets ignorent une version qu'ils ne connaissent pas.
  static const int version = 1;

  /// Clé de l'instantané dans l'espace partagé (UserDefaults du groupe
  /// d'apps sur iOS, préférences de home_widget sur Android).
  static const String storageKey = 'decisions_snapshot';

  /// Instant d'écriture par l'app.
  final DateTime savedAt;

  /// Décisions, de la plus récente à la plus ancienne.
  final List<WidgetDecision> decisions;

  /// Lit un instantané ; renvoie `null` s'il est illisible ou d'une autre
  /// version. Les décisions malformées sont ignorées.
  static WidgetSnapshot? tryFromJson(Object? json) {
    if (json is! Map<String, Object?> || json['version'] != version) {
      return null;
    }
    final savedAt = DateTime.tryParse('${json['savedAt']}');
    final decisions = json['decisions'];
    if (savedAt == null || decisions is! List) return null;
    return WidgetSnapshot(
      savedAt: savedAt,
      decisions: [
        for (final d in decisions)
          if (d is Map<String, Object?>) ?WidgetDecision.tryFromJson(d),
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'decisions': [for (final d in decisions) d.toJson()],
  };
}

/// Une décision telle que l'affichent les widgets.
class WidgetDecision {
  const WidgetDecision({
    required this.id,
    required this.result,
    required this.date,
    required this.title,
    this.stage,
    this.explanation,
  });

  /// Les widgets natifs ne connaissent pas le mode de vote : la mention
  /// « à main levée » est ajoutée à l'étape, qu'ils affichent déjà.
  factory WidgetDecision.fromSummary(DecisionSummary d) => WidgetDecision(
    id: d.id,
    result: d.result,
    date: d.date,
    title: _capitalize(d.displayTitle.trim()),
    stage: switch ((d.stage, voteModeLabel(d.voteMode))) {
      (final stage?, final mode?) => '$stage · $mode',
      (null, final mode?) => _capitalize(mode),
      (final stage, null) => stage,
    },
  );

  /// Identifiant de la décision (deep link vers le détail) : celui du
  /// scrutin, ou de l'acte de décision pour un vote à main levée.
  final String id;

  final VoteResult result;

  /// Jour du vote. Les widgets le formatent eux-mêmes, pour pouvoir passer à
  /// une date relative (« aujourd'hui », « il y a 3 jours ») sans l'app.
  final DateTime date;

  /// Titre principal, déjà prêt à afficher.
  final String title;

  /// Étape de la procédure (« 1re lecture à l'AN »), si connue, suivie de
  /// « · à main levée » pour un vote sans scrutin public.
  final String? stage;

  /// Phrase d'explication en langage simple, si disponible.
  final String? explanation;

  static WidgetDecision? tryFromJson(Map<String, Object?> json) {
    final id = json['id'];
    final result = VoteResult.tryParse(json['result']);
    final date = DateTime.tryParse('${json['date']}T00:00:00Z');
    final title = json['title'];
    final stage = json['stage'];
    final explanation = json['explanation'];
    if (id is! String || result == null || date == null || title is! String) {
      return null;
    }
    return WidgetDecision(
      id: id,
      result: result,
      date: date,
      title: title,
      stage: stage is String ? stage : null,
      explanation: explanation is String ? explanation : null,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'result': result.json,
    'date': formatDate(date),
    'title': title,
    'stage': ?stage,
    'explanation': ?explanation,
  };
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
