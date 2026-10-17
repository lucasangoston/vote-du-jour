import 'package:vote_contract/vote_contract.dart';

/// Retenir les propositions de résolution (article 34-1, commissions
/// d'enquête) ? Décision produit en attente : sans portée normative, mais très
/// médiatisées. La règle s'applique de la même façon à « la proposition de
/// résolution… » et à « l'ensemble de la proposition de résolution… ».
const retainResolutions = true;

/// Résultat de la classification d'un scrutin.
sealed class Classification {
  const Classification();
}

/// Le scrutin est une décision à publier.
class Retained extends Classification {
  const Retained(this.type, this.result);

  final DecisionType type;

  /// Résultat pour le texte, tel qu'il doit être affiché (voir
  /// [DecisionSummary.result]) : il peut différer du sort du scrutin, par
  /// exemple une motion de rejet préalable adoptée vaut rejet du texte.
  final VoteResult result;

  @override
  bool operator ==(Object other) =>
      other is Retained && other.type == type && other.result == result;

  @override
  int get hashCode => Object.hash(type, result);

  @override
  String toString() => 'Retained(${type.name}, ${result.name})';
}

/// Le scrutin n'est pas publié.
class Excluded extends Classification {
  const Excluded(this.reason);

  final ExclusionReason reason;

  @override
  bool operator ==(Object other) => other is Excluded && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'Excluded(${reason.name})';
}

enum ExclusionReason {
  amendement,
  sousAmendement,
  article,

  /// Suspension de séance, seconde délibération, prolongation de séance.
  procedure,

  /// Partie d'une loi de finances ou de financement de la sécurité sociale qui
  /// ne fait pas tomber le texte (adoptée, ou autre que la première).
  partieBudget,

  /// Motion de rejet préalable rejetée : l'examen du texte continue.
  rejetPrealableRejete,

  /// Proposition de résolution, si [retainResolutions] est faux.
  resolution,

  /// Tournure inconnue : à journaliser pour relecture.
  nonReconnu,
}

/// Classe un scrutin d'après son intitulé officiel, le code de son type de
/// vote (`SPO` ordinaire, `SPS` solennel, `MOC` motion de censure) et son sort.
///
/// Le jeu de données n'a pas de champ « décision » : la classification repose
/// sur le début de l'intitulé, après normalisation (apostrophes
/// typographiques, espaces insécables, casse). Règle issue de l'analyse des
/// 8 877 scrutins de la 17e législature (spike #15).
Classification classifyScrutin({
  required String titre,
  required String? codeTypeVote,
  required VoteResult sort,
}) {
  var t = normalizeTitle(titre);
  // « sur la motion de rejet préalable… » (scrutin 5156).
  if (t.startsWith('sur ')) t = t.substring(4);

  // Le code MOC désigne exactement les motions de censure ; le titre sert de
  // repli quand le code est inconnu (site de l'Assemblée).
  if (codeTypeVote == 'MOC' || t.startsWith('la motion de censure')) {
    return Retained(DecisionType.motionDeCensure, sort);
  }

  // Amendements, sous-amendements et articles, y compris avec les coquilles
  // relevées dans les titres officiels (« amenedement », « sous-amendmeent »,
  // « aticle »).
  if (_sousAmendement.hasMatch(t)) {
    return const Excluded(ExclusionReason.sousAmendement);
  }
  if (_amendement.hasMatch(t)) {
    return const Excluded(ExclusionReason.amendement);
  }
  if (_article.hasMatch(t)) {
    return const Excluded(ExclusionReason.article);
  }

  if (_procedure.any(t.startsWith)) {
    return const Excluded(ExclusionReason.procedure);
  }

  // Le rejet de la première partie d'une loi de finances (ou de financement de
  // la sécurité sociale) fait tomber tout le texte ; les autres votes sur une
  // partie sont des étapes intermédiaires.
  if (_budgetPart.firstMatch(t) case final match?) {
    return match.group(1) == 'première' && sort == VoteResult.rejete
        ? const Retained(DecisionType.premierePartieBudget, VoteResult.rejete)
        : const Excluded(ExclusionReason.partieBudget);
  }

  // Une motion de rejet préalable adoptée vaut rejet du texte.
  if (t.startsWith('la motion de rejet')) {
    return sort == VoteResult.adopte
        ? const Retained(DecisionType.rejetPrealable, VoteResult.rejete)
        : const Excluded(ExclusionReason.rejetPrealableRejete);
  }

  if (t.startsWith('la déclaration du gouvernement') ||
      t.startsWith('la déclaration de politique générale')) {
    return Retained(DecisionType.declarationGouvernement, sort);
  }

  if (_resolution.hasMatch(t)) {
    return retainResolutions
        ? Retained(DecisionType.resolution, sort)
        : const Excluded(ExclusionReason.resolution);
  }

  if (_wholeText.any(t.startsWith)) {
    return Retained(DecisionType.ensembleTexte, sort);
  }

  // Garde-fou : un scrutin solennel est toujours une décision majeure ; une
  // tournure inconnue ne doit pas la faire disparaître.
  if (codeTypeVote == 'SPS') return Retained(DecisionType.autre, sort);

  return const Excluded(ExclusionReason.nonReconnu);
}

final _sousAmendement = RegExp(r'^le sous-amen[a-z]*');
final _amendement = RegExp(r"^l'amen[a-z]*ment");
final _article = RegExp(r"^l'ar?ticle");

const _procedure = [
  'la demande de', // suspension de séance, seconde délibération
  'la proposition du gouvernement de prolonger',
];

final _budgetPart = RegExp(
  r"^(?:l'ensemble (?:de la|du) )?(?:la )?(première|deuxième|troisième|quatrième) partie",
);

final _resolution = RegExp(r"^(?:l'ensemble de )?la proposition de résolution");

const _wholeText = ["l'ensemble", 'la proposition de loi', 'le projet de loi'];

/// Normalise un intitulé pour la comparaison : apostrophes typographiques,
/// espaces (y compris insécables), casse.
String normalizeTitle(String s) => s
    .replaceAll(RegExp('[‘’ʼ`]'), "'")
    .replaceAll(RegExp(r'[\s  ]+'), ' ')
    .trim()
    .toLowerCase();
