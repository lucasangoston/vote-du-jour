import 'package:vote_contract/vote_contract.dart';

import 'decision_labels.dart';
import 'decision_selector.dart';
import 'dossier_index.dart';
import 'scrutin.dart';

/// Construit l'index publié : les [limit] décisions les plus récentes parmi
/// [scrutins], de la plus récente à la plus ancienne (à date égale, le numéro
/// de scrutin le plus élevé d'abord, car l'open data ne donne pas l'heure).
///
/// [dossiers] fournit le titre court et l'étape ; sans lui, ils sont tirés
/// de l'intitulé du scrutin.
DecisionIndex buildDecisionIndex(
  Iterable<Scrutin> scrutins, {
  required DateTime generatedAt,
  DossierIndex? dossiers,
  int limit = maxIndexDecisions,
}) {
  final decisions = <DecisionSummary>[
    for (final s in scrutins)
      if (_classify(s) case Retained(:final type, :final result))
        _summary(s, type, result, dossiers),
  ];
  decisions.sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    return byDate != 0 ? byDate : b.numero.compareTo(a.numero);
  });
  return DecisionIndex(
    generatedAt: generatedAt,
    decisions: decisions.take(limit).toList(),
  );
}

/// Scrutins dont l'intitulé n'est reconnu par aucune règle : à relire, une
/// nouvelle tournure peut cacher une décision.
List<Scrutin> unrecognizedScrutins(Iterable<Scrutin> scrutins) => [
  for (final s in scrutins)
    if (_classify(s) == const Excluded(ExclusionReason.nonReconnu)) s,
];

DecisionSummary _summary(
  Scrutin s,
  DecisionType type,
  VoteResult result,
  DossierIndex? dossiers,
) {
  final labels = labelDecision(
    type: type,
    titre: s.titre,
    link: dossiers?.link(
      scrutinUid: s.uid,
      date: s.date,
      titre: s.titre,
      dossierRef: s.dossierRef,
    ),
  );
  return DecisionSummary(
    id: s.uid,
    numero: s.numero,
    type: type,
    status: DecisionStatus.confirmee,
    result: result,
    date: s.date,
    officialTitle: s.titre,
    sourceUrl: scrutinPageUrl(s.numero),
    shortTitle: labels.shortTitle,
    stage: labels.stage,
    dossierUrl: labels.dossierUrl,
  );
}

Classification _classify(Scrutin s) => classifyScrutin(
  titre: s.titre,
  codeTypeVote: s.codeTypeVote,
  sort: s.result,
);

/// Page officielle d'un scrutin de la 17e législature.
String scrutinPageUrl(int numero) =>
    'https://www.assemblee-nationale.fr/dyn/17/scrutins/$numero';
