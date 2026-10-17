import 'package:vote_contract/vote_contract.dart';

import 'decision_selector.dart' show normalizeTitle;
import 'dossier_index.dart';

/// Libellés lisibles d'une décision : titre court et étape (ou étiquette).
class DecisionLabels {
  const DecisionLabels({
    required this.shortTitle,
    required this.stage,
    this.dossierUrl,
  });

  /// Voir [DecisionSummary.shortTitle].
  final String shortTitle;

  /// Voir [DecisionSummary.stage].
  final String stage;

  /// Voir [DecisionSummary.dossierUrl].
  final String? dossierUrl;

  @override
  String toString() => 'DecisionLabels($shortTitle | $stage)';
}

/// Étiquette des propositions de résolution, à la place d'une étape : elles
/// n'ont pas de valeur de loi (décision produit, issue #7).
const resolutionLabel = 'Résolution (sans valeur de loi)';

/// Calcule le titre court et l'étape d'une décision de type [type], à partir
/// de son intitulé officiel [titre] et, s'il est connu, de son dossier
/// ([link]).
///
/// L'étape vient de l'acte du dossier qui cite le scrutin, sinon de la
/// parenthèse finale de l'intitulé (« (première lecture) »). Les types sans
/// lecture (motion de censure, déclaration du Gouvernement, résolution)
/// reçoivent une étiquette. Aucun libellé n'annonce une loi votée : l'étape
/// est celle du vote à l'Assemblée.
DecisionLabels labelDecision({
  required DecisionType type,
  required String titre,
  DossierLink? link,
}) {
  final lecture = link?.lecture ?? Lecture.fromScrutinTitle(titre);
  final textDossier = link != null && link.isText ? link.dossier : null;
  final textTitle = textDossier != null
      ? cleanDossierTitle(textDossier.title)
      : _votedTextTitle(titre);
  String withLecture(String label) =>
      lecture == null ? label : '$label, ${lecture.label}';

  final (String shortTitle, String stage) = switch (type) {
    DecisionType.ensembleTexte => (
      textTitle ?? _cleanOfficialTitle(titre),
      lecture?.label ?? "Vote sur l'ensemble du texte",
    ),
    DecisionType.autre => (
      textTitle ?? _cleanOfficialTitle(titre),
      lecture?.label ?? 'Scrutin solennel',
    ),
    DecisionType.resolution => (
      textTitle ?? _cleanOfficialTitle(titre),
      resolutionLabel,
    ),
    DecisionType.rejetPrealable => (
      textTitle ?? _cleanOfficialTitle(titre),
      withLecture('Motion de rejet préalable'),
    ),
    DecisionType.premierePartieBudget => (
      textTitle ?? _cleanOfficialTitle(titre),
      withLecture('Première partie du budget'),
    ),
    DecisionType.motionDeCensure => (
      _censureTitle(titre, textDossier),
      'Motion de censure',
    ),
    DecisionType.declarationGouvernement => (
      _declarationTitle(titre),
      normalizeTitle(titre).contains('politique générale')
          ? 'Déclaration de politique générale'
          : 'Déclaration du Gouvernement',
    ),
  };
  return DecisionLabels(
    shortTitle: shortTitle,
    stage: stage,
    dossierUrl: textDossier?.url,
  );
}

/// Titre de dossier sans la formule « Proposition de loi visant à » :
/// « Proposition de loi visant à sortir la France du piège du narcotrafic »
/// devient « Sortir la France du piège du narcotrafic ».
String cleanDossierTitle(String title) {
  final t = title.trim().replaceAll(RegExp(r'\s+'), ' ');
  final match = _proposalFormula.firstMatch(t);
  return match == null ? t : _capitalize(t.substring(match.end));
}

final _proposalFormula = RegExp(
  r'^proposition de loi (?:organique |constitutionnelle )?(?:visant|tendant) à ',
  caseSensitive: false,
);

/// Le texte nommé par l'intitulé du scrutin (« la motion de rejet
/// préalable, déposée par …, de la proposition de loi visant à … (première
/// lecture). » → « Proposition de loi visant à … »).
String? _votedTextTitle(String titre) {
  final match = RegExp(
    r'(?:proposition de (?:loi|résolution)|projet de loi).*$',
    caseSensitive: false,
  ).firstMatch(titre.trim());
  return match == null ? null : _cleanOfficialTitle(match.group(0)!);
}

/// Intitulé sans « l'ensemble de », sans parenthèse ni point final.
String _cleanOfficialTitle(String titre) {
  var t = titre.trim().replaceAll(RegExp(r'\s+'), ' ');
  t = t.replaceFirst(RegExp(r'\s*\([^()]*\)\s*\.?$'), '');
  t = t.replaceFirst(RegExp(r'\.$'), '');
  t = t.replaceFirst(
    RegExp(r"^l['’]ensemble (?:de la |du |de l['’])", caseSensitive: false),
    '',
  );
  return _capitalize(t);
}

/// « Motion de censure : Projet de loi de finances pour 2026 » après un
/// 49.3, « Motion de censure déposée par Mme X et 57 députés » sinon.
String _censureTitle(String titre, Dossier? textDossier) {
  if (textDossier != null) {
    return 'Motion de censure : ${cleanDossierTitle(textDossier.title)}';
  }
  final t = _cleanOfficialTitle(titre);
  final authors = RegExp(r',? par (.+)$').firstMatch(t);
  return authors == null
      ? 'Motion de censure'
      : 'Motion de censure déposée par ${authors.group(1)}';
}

/// « la déclaration du Gouvernement portant sur X (application de l'article
/// 50-1…). » → « Déclaration du Gouvernement sur X ».
String _declarationTitle(String titre) => _capitalize(
  _cleanOfficialTitle(titre)
      .replaceFirst(RegExp('^la ', caseSensitive: false), '')
      .replaceFirst(' portant sur ', ' sur '),
);

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
