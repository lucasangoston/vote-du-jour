import 'decision.dart';

/// Étape d'un texte en lecture définitive, telle que publiée dans
/// [DecisionSummary.stage].
const definitiveLectureStage = "Lecture définitive à l'AN";

/// Étape d'un texte de compromis de la commission mixte paritaire, telle que
/// publiée dans [DecisionSummary.stage].
const cmpStage = 'Texte de compromis (CMP)';

/// Étapes qui rendent un vote sur un texte important.
const _importantStages = [definitiveLectureStage, cmpStage];

/// La décision [d] est-elle un vote important (#34) ? Même règle pour les
/// notifications et pour les posts de la content factory (#107).
///
/// - scrutin public solennel ([DecisionSummary.solennel]) ;
/// - motion de censure ;
/// - texte en lecture définitive ou texte de compromis (CMP), adopté ou
///   rejeté.
///
/// Jamais : vote à main levée, proposition de résolution, décision
/// provisoire (elle compte à sa confirmation, pour ne jamais annoncer un
/// résultat faux).
bool isImportantDecision(DecisionSummary d) {
  if (d.status != DecisionStatus.confirmee) return false;
  if (d.voteMode != VoteMode.scrutinPublic) return false;
  if (d.type == DecisionType.resolution) return false;
  if (d.solennel) return true;
  if (d.type == DecisionType.motionDeCensure) return true;
  final stage = d.stage;
  return stage != null &&
      (d.type == DecisionType.ensembleTexte ||
          d.type == DecisionType.rejetPrealable) &&
      _importantStages.any(stage.endsWith);
}
