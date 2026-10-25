/// Résumé d'une décision en langage simple, rédigé automatiquement par un
/// modèle de langage (ticket #9) avec une consigne de neutralité, sans
/// relecture humaine.
///
/// Dans l'index (`v1/latest.json`), seuls [title], [shortTitle] et
/// [explanation] sont publiés ; les [points] ne figurent que dans le fichier de détail de la
/// décision.
class PlainSummary {
  const PlainSummary({
    required this.title,
    required this.explanation,
    required this.promptVersion,
    this.shortTitle,
    this.points = const [],
  });

  /// Titre lisible, court et sans jargon.
  final String title;

  /// Titre plus court encore, pour les widgets et la liste (ticket #72) :
  /// [shortTitleMaxLength] caractères au plus. `null` pour les résumés
  /// antérieurs, ou quand le modèle a rendu un titre trop long : l'app se
  /// rabat alors sur [title].
  final String? shortTitle;

  /// Une phrase d'explication.
  final String explanation;

  /// Ce que prévoit le texte, en 3 ou 4 points. Vide dans l'index, et quand
  /// le résumé n'a pu s'appuyer que sur l'intitulé (motion de censure,
  /// texte introuvable).
  final List<String> points;

  /// Version de la consigne donnée au modèle (fichier versionné dans le
  /// dépôt, `backend/lib/src/summary/summary_prompt.dart`).
  final int promptVersion;

  /// Lit un résumé ; `null` s'il est absent ou malformé (la décision reste
  /// lisible, sans résumé). Un point illisible est ignoré.
  static PlainSummary? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final title = json['title'];
    final explanation = json['explanation'];
    final promptVersion = json['promptVersion'];
    if (title is! String ||
        title.trim().isEmpty ||
        explanation is! String ||
        explanation.trim().isEmpty ||
        promptVersion is! int) {
      return null;
    }
    final points = json['points'];
    final shortTitle = json['shortTitle'];
    return PlainSummary(
      title: title,
      shortTitle: shortTitle is String && isValidShortTitle(shortTitle)
          ? shortTitle
          : null,
      explanation: explanation,
      promptVersion: promptVersion,
      points: [
        if (points is List)
          for (final p in points)
            if (p is String && p.trim().isNotEmpty) p,
      ],
    );
  }

  /// [withPoints] : `false` pour l'index, `true` pour le fichier de détail.
  Map<String, Object?> toJson({bool withPoints = true}) => {
    'title': title,
    'shortTitle': ?shortTitle,
    'explanation': explanation,
    if (withPoints) 'points': points,
    'promptVersion': promptVersion,
  };

  @override
  bool operator ==(Object other) =>
      other is PlainSummary &&
      other.title == title &&
      other.shortTitle == shortTitle &&
      other.explanation == explanation &&
      other.promptVersion == promptVersion &&
      _sameList(other.points, points);

  @override
  int get hashCode => Object.hash(
    title,
    shortTitle,
    explanation,
    promptVersion,
    Object.hashAll(points),
  );

  @override
  String toString() =>
      'PlainSummary(title: $title, shortTitle: $shortTitle, explanation: $explanation, '
      'points: $points, promptVersion: $promptVersion)';
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Longueur maximale de [PlainSummary.shortTitle] : deux lignes d'un petit
/// widget.
const shortTitleMaxLength = 35;

/// Un titre court publiable : non vide, [shortTitleMaxLength] caractères au
/// plus.
bool isValidShortTitle(String title) =>
    title.trim().isNotEmpty && title.length <= shortTitleMaxLength;
