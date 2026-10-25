import 'decision.dart' show formatDate;
import 'plain_summary.dart';

/// Sort d'un article du texte en débat (#55).
enum ArticleOutcome {
  /// Article adopté au scrutin public.
  adopte('adopte'),

  /// Article rejeté au scrutin public.
  rejete('rejete'),

  /// Amendement de suppression de l'article adopté au scrutin public.
  supprime('supprime');

  const ArticleOutcome(this.json);

  final String json;

  static ArticleOutcome? tryParse(Object? value) =>
      ArticleOutcome.values.where((o) => o.json == value).firstOrNull;
}

/// Un article du texte en débat, voté au scrutin public.
class DebatedArticle {
  const DebatedArticle({
    required this.number,
    required this.outcome,
    required this.date,
    required this.scrutinRef,
  });

  /// Numéro de l'article tel qu'écrit dans l'intitulé du scrutin : « 4 »,
  /// « 40 », « liminaire », « 3 bis », « 1er », « premier ».
  final String number;

  final ArticleOutcome outcome;

  /// Jour du vote, à minuit UTC.
  final DateTime date;

  /// Scrutin du vote (`VTANR5L17V8892`).
  final String scrutinRef;

  /// Numéro du scrutin tiré de [scrutinRef], ou `null`.
  int? get scrutinNumero =>
      int.tryParse(RegExp(r'(\d+)$').firstMatch(scrutinRef)?.group(1) ?? '');

  /// Lit un article ; `null` s'il est malformé ou d'un sort inconnu (ajouté
  /// par une version plus récente du job).
  static DebatedArticle? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final number = json['number'];
    final outcome = ArticleOutcome.tryParse(json['outcome']);
    final date = json['date'] is String
        ? DateTime.tryParse('${json['date']}T00:00:00Z')
        : null;
    final scrutinRef = json['scrutinRef'];
    if (number is! String ||
        number.trim().isEmpty ||
        outcome == null ||
        date == null ||
        scrutinRef is! String ||
        scrutinRef.isEmpty) {
      return null;
    }
    return DebatedArticle(
      number: number,
      outcome: outcome,
      date: date,
      scrutinRef: scrutinRef,
    );
  }

  Map<String, Object?> toJson() => {
    'number': number,
    'outcome': outcome.json,
    'date': formatDate(date),
    'scrutinRef': scrutinRef,
  };

  @override
  String toString() => 'DebatedArticle($number ${outcome.json} $scrutinRef)';
}

/// Le texte en débat à l'Assemblée (bloc `inDebate` de l'index, #55) : celui
/// discuté lors de la séance en cours ou de la dernière séance, et ses
/// articles votés au scrutin public.
class InDebate {
  const InDebate({
    required this.dossierRef,
    required this.shortTitle,
    required this.dossierUrl,
    required this.seanceRef,
    required this.startsAt,
    this.articles = const [],
    this.summary,
  });

  /// Dossier législatif du texte (`DLR5L17N54951`).
  final String dossierRef;

  /// Titre court et lisible, comme celui du bloc « À venir ».
  final String shortTitle;

  /// Page officielle du dossier législatif.
  final String dossierUrl;

  /// Séance en cours ou dernière séance où le texte a été discuté
  /// (`RUANR5L17S2027IDS30954`).
  final String seanceRef;

  /// Début de cette séance (instant UTC).
  final DateTime startsAt;

  /// Articles votés au scrutin public, un par article (son dernier vote), du
  /// plus récent au plus ancien. Vide si aucun article n'a encore été voté.
  final List<DebatedArticle> articles;

  /// Résumé du texte (#73), rédigé par le même modèle et avec la même
  /// consigne que celui d'une décision, et repris par la décision sur
  /// l'ensemble du texte. Les [PlainSummary.points] sont publiés ici, faute
  /// de fichier de détail. Champ optionnel : absent tant que le texte n'est
  /// pas résumé, ou sans texte exploitable.
  final PlainSummary? summary;

  /// Le même bloc avec le résumé [summary].
  InDebate withSummary(PlainSummary? summary) => InDebate(
    dossierRef: dossierRef,
    shortTitle: shortTitle,
    dossierUrl: dossierUrl,
    seanceRef: seanceRef,
    startsAt: startsAt,
    articles: articles,
    summary: summary,
  );

  /// Lit le bloc ; `null` s'il est malformé. Un article ou un résumé
  /// illisible est ignoré.
  static InDebate? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final dossierRef = json['dossierRef'];
    final shortTitle = json['shortTitle'];
    final dossierUrl = json['dossierUrl'];
    final seanceRef = json['seanceRef'];
    final startsAt = json['startsAt'] is String
        ? DateTime.tryParse(json['startsAt'] as String)
        : null;
    final articles = json['articles'];
    if (dossierRef is! String ||
        shortTitle is! String ||
        shortTitle.trim().isEmpty ||
        dossierUrl is! String ||
        seanceRef is! String ||
        startsAt == null) {
      return null;
    }
    return InDebate(
      dossierRef: dossierRef,
      shortTitle: shortTitle,
      dossierUrl: dossierUrl,
      seanceRef: seanceRef,
      startsAt: startsAt.toUtc(),
      articles: [
        if (articles is List)
          for (final a in articles) ?DebatedArticle.tryFromJson(a),
      ],
      summary: PlainSummary.tryFromJson(json['summary']),
    );
  }

  Map<String, Object?> toJson() => {
    'dossierRef': dossierRef,
    'shortTitle': shortTitle,
    'dossierUrl': dossierUrl,
    'seanceRef': seanceRef,
    'startsAt': startsAt.toUtc().toIso8601String(),
    'articles': [for (final a in articles) a.toJson()],
    'summary': ?summary?.toJson(),
  };

  @override
  String toString() =>
      'InDebate($dossierRef $shortTitle, ${articles.length} articles)';
}
