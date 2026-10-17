import 'package:vote_contract/vote_contract.dart';

import 'decision_labels.dart';
import 'decision_selector.dart';
import 'dossier_index.dart';
import 'scrutin.dart';

/// Construit l'index publié : les [limit] décisions les plus récentes parmi
/// les [scrutins] retenus et les textes adoptés à main levée, de la plus
/// récente à la plus ancienne.
///
/// L'open data ne donne pas l'heure : à date égale, les scrutins publics
/// passent d'abord (numéro le plus élevé en tête), puis les votes à main
/// levée (identifiant d'acte le plus élevé en tête).
///
/// [dossiers] fournit le titre court, l'étape et les textes adoptés à main
/// levée ; sans lui, les libellés sont tirés de l'intitulé du scrutin et
/// aucun vote à main levée n'est publié.
DecisionIndex buildDecisionIndex(
  Iterable<Scrutin> scrutins, {
  required DateTime generatedAt,
  DossierIndex? dossiers,
  int limit = maxIndexDecisions,
}) {
  final decisions = <DecisionSummary>[];
  // Textes votés par scrutin public, par jour : dossier rattaché, ou
  // intitulé faute de rattachement. Un texte adopté ce jour-là dans ce
  // dossier l'a été par ce scrutin, pas à main levée.
  final byScrutin = <(String, DateTime)>{};
  final unlinked = <DateTime, List<String>>{};
  for (final s in scrutins) {
    final classification = _classify(s);
    final retained = classification is Retained;
    if (!retained && !_isArticleUnique(s.titre)) continue;
    final link = dossiers?.link(
      scrutinUid: s.uid,
      date: s.date,
      titre: s.titre,
      dossierRef: s.dossierRef,
    );
    if (link != null) {
      byScrutin.add((link.dossier.uid, s.date));
    } else {
      unlinked.putIfAbsent(s.date, () => []).add(s.titre);
    }
    if (classification case Retained(:final type, :final result)) {
      decisions.add(_summary(s, type, result, link));
    }
  }
  // Textes adoptés à main levée, sauf s'ils ont eu un scrutin public le même
  // jour (voir ci-dessus).
  for (final a in dossiers?.mainLeveeAdoptions() ?? <MainLeveeAdoption>[]) {
    final titles = [a.dossier.title, ?a.textTitle];
    final hasScrutin =
        byScrutin.contains((a.dossier.uid, a.date)) ||
        (unlinked[a.date] ?? const <String>[]).any(
          (titre) => sameVotedText(titre, titles),
        );
    if (!hasScrutin) decisions.add(_mainLeveeSummary(a));
  }
  decisions.sort(compareDecisions);
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

/// Ordre de l'index : date décroissante ; à date égale, scrutins publics
/// (numéro décroissant) puis votes à main levée (identifiant décroissant).
int compareDecisions(DecisionSummary a, DecisionSummary b) {
  final byDate = b.date.compareTo(a.date);
  if (byDate != 0) return byDate;
  return switch ((a.numero, b.numero)) {
    (final x?, final y?) => y.compareTo(x),
    (_?, null) => -1,
    (null, _?) => 1,
    (null, null) => b.id.compareTo(a.id),
  };
}

DecisionSummary _summary(
  Scrutin s,
  DecisionType type,
  VoteResult result,
  DossierLink? link,
) {
  final labels = labelDecision(type: type, titre: s.titre, link: link);
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

/// Texte adopté à main levée : résultat « adopté », sans numéro de scrutin
/// ni décompte. L'étape suit la même règle que pour un scrutin (lecture de
/// l'acte, étiquette des résolutions) ; la page officielle est celle du
/// dossier.
DecisionSummary _mainLeveeSummary(MainLeveeAdoption a) {
  final type = a.isResolution
      ? DecisionType.resolution
      : DecisionType.ensembleTexte;
  final labels = labelDecision(
    type: type,
    titre: a.officialTitle,
    link: DossierLink(dossier: a.dossier, lecture: a.lecture, isText: true),
  );
  return DecisionSummary(
    id: a.acteUid,
    voteMode: VoteMode.mainLevee,
    type: type,
    status: DecisionStatus.confirmee,
    result: VoteResult.adopte,
    date: a.date,
    officialTitle: a.officialTitle,
    sourceUrl: a.dossier.url,
    shortTitle: labels.shortTitle,
    stage: labels.stage,
    dossierUrl: labels.dossierUrl,
  );
}

/// Scrutin sur l'article unique d'un texte : il vaut vote sur l'ensemble
/// (le texte n'a qu'un article), même si le sélecteur ne le retient pas. Le
/// texte n'a donc pas été adopté à main levée.
bool _isArticleUnique(String titre) =>
    normalizeTitle(titre).startsWith("l'article unique ");

Classification _classify(Scrutin s) => classifyScrutin(
  titre: s.titre,
  codeTypeVote: s.codeTypeVote,
  sort: s.result,
);

/// Page officielle d'un scrutin de la 17e législature.
String scrutinPageUrl(int numero) =>
    'https://www.assemblee-nationale.fr/dyn/17/scrutins/$numero';
