import 'package:vote_contract/vote_contract.dart';

import 'decision_selector.dart';
import 'scrutin.dart';

/// Construit l'index publié : les [limit] décisions les plus récentes parmi
/// [scrutins], de la plus récente à la plus ancienne (à date égale, le numéro
/// de scrutin le plus élevé d'abord, car l'open data ne donne pas l'heure).
DecisionIndex buildDecisionIndex(
  Iterable<Scrutin> scrutins, {
  required DateTime generatedAt,
  int limit = maxIndexDecisions,
}) {
  final decisions = <DecisionSummary>[
    for (final s in scrutins)
      if (_classify(s) case Retained(:final type, :final result))
        DecisionSummary(
          id: s.uid,
          numero: s.numero,
          type: type,
          status: DecisionStatus.confirmee,
          result: result,
          date: s.date,
          officialTitle: s.titre,
          sourceUrl: scrutinPageUrl(s.numero),
        ),
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

Classification _classify(Scrutin s) => classifyScrutin(
  titre: s.titre,
  codeTypeVote: s.codeTypeVote,
  sort: s.result,
);

/// Page officielle d'un scrutin de la 17e législature.
String scrutinPageUrl(int numero) =>
    'https://www.assemblee-nationale.fr/dyn/17/scrutins/$numero';
