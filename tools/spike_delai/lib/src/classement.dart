/// Classement d'un scrutin à partir du début de son titre.
///
/// Reprend la règle du PRD (#1, module « Sélecteur de décisions ») pour
/// mesurer sa fiabilité sur l'historique : les catégories retenues sont
/// l'ensemble d'un texte, les motions et les déclarations du Gouvernement ;
/// les amendements, sous-amendements et articles sont rejetés ; tout le reste
/// est « non classé » et doit être examiné à la main.
library;

enum Categorie {
  ensemble('ensemble', retenue: true),
  motionCensure('motion_censure', retenue: true),
  autreMotion('autre_motion', retenue: true),
  declarationGouvernement('declaration_gouvernement', retenue: true),
  amendement('amendement', retenue: false),
  sousAmendement('sous_amendement', retenue: false),
  article('article', retenue: false),
  nonClasse('non_classe', retenue: false);

  const Categorie(this.code, {required this.retenue});

  /// Identifiant stable, écrit dans les CSV.
  final String code;

  /// Vrai si la règle du PRD garderait ce scrutin comme décision.
  final bool retenue;
}

/// Normalise un titre : apostrophes typographiques, espaces insécables,
/// casse, espaces multiples.
String normaliserTitre(String titre) => titre
    .replaceAll(RegExp('[’‘ʼ`]'), "'")
    .replaceAll(RegExp('[  ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();

/// Retire le préfixe « Scrutin public n°1234 sur » des titres de la liste du
/// site, pour retrouver le titre tel qu'il figure dans le jeu de données.
String titreSansPrefixe(String titre) => titre
    .replaceFirst(
      RegExp(r'^\s*scrutin\s+[^\n]*?n°\s*\d+\s+sur\s+', caseSensitive: false),
      '',
    )
    .trim();

Categorie classer(String titre) {
  final t = normaliserTitre(titreSansPrefixe(titre));
  if (t.startsWith("l'ensemble")) return Categorie.ensemble;
  if (t.startsWith('la motion de censure')) return Categorie.motionCensure;
  if (t.startsWith('la motion')) return Categorie.autreMotion;
  if (t.startsWith('la déclaration du gouvernement')) {
    return Categorie.declarationGouvernement;
  }
  if (t.startsWith('le sous-amendement')) return Categorie.sousAmendement;
  if (t.startsWith("l'amendement")) return Categorie.amendement;
  if (t.startsWith("l'article")) return Categorie.article;
  return Categorie.nonClasse;
}
