import 'package:vote_contract/vote_contract.dart';

/// Au plus autant de posts par jour (#108).
const maxPostsPerDay = 3;

/// Une décision plus ancienne n'est plus proposée en post.
const postMaxAge = Duration(days: 7);

/// Écart serré : au plus cette part des suffrages exprimés entre pour et
/// contre.
const tightMarginRatio = 0.03;

/// Décisions du jour pour la content factory (#106, #108), dans l'ordre de
/// publication. Déterministe, sur le contrat publié seulement :
///
/// 1. éligibilité : confirmée, résumée, scrutin public dont le détail a des
///    groupes et des sièges, de [postMaxAge] au plus, absente de [handled]
///    (ids déjà publiés ou jetés dans les issues des 7 derniers jours) ;
/// 2. classement : [isImportantDecision], puis les votes qui décident du
///    sort d'un texte entier, puis les résolutions et le reste ; à égalité,
///    écart serré, puis configuration inhabituelle, puis arguments, puis la
///    plus récente ;
/// 3. diversité : une décision par dossier ([DecisionSummary.dossierUrl]),
///    au plus [maxPostsPerDay].
///
/// [details] : fichiers de détail par id de décision ; une décision sans
/// détail n'est pas éligible.
List<DecisionDetail> selectPostDecisions({
  required DecisionIndex index,
  required Map<String, DecisionDetail> details,
  required Set<String> handled,
  required DateTime now,
}) {
  final oldest = now.subtract(postMaxAge);
  final eligible = [
    for (final d in index.decisions)
      if (details[d.id] case final detail?
          when _isEligible(d, detail, handled, oldest))
        detail,
  ]..sort(_compare);

  final dossiers = <String>{};
  return [
    for (final detail in eligible)
      if (dossiers.add(detail.decision.dossierUrl ?? detail.decision.id))
        detail,
  ].take(maxPostsPerDay).toList();
}

bool _isEligible(
  DecisionSummary d,
  DecisionDetail detail,
  Set<String> handled,
  DateTime oldest,
) =>
    d.status == DecisionStatus.confirmee &&
    d.summary != null &&
    d.voteMode == VoteMode.scrutinPublic &&
    d.count != null &&
    detail.groups.isNotEmpty &&
    (detail.seats?.isNotEmpty ?? false) &&
    !d.date.isBefore(oldest) &&
    !handled.contains(d.id);

/// Rang de priorité : 0 vote important, 1 sort d'un texte entier, 2 le
/// reste (résolutions, intitulé non reconnu).
int postPriority(DecisionSummary d) {
  if (isImportantDecision(d)) return 0;
  return switch (d.type) {
    DecisionType.ensembleTexte ||
    DecisionType.rejetPrealable ||
    DecisionType.premierePartieBudget ||
    DecisionType.declarationGouvernement => 1,
    DecisionType.motionDeCensure ||
    DecisionType.resolution ||
    DecisionType.autre => 2,
  };
}

/// Écart serré : pour et contre à au plus [tightMarginRatio] des exprimés.
/// Jamais pour une motion de censure (seuls les pour y comptent).
bool isTightVote(DecisionSummary d) {
  final c = d.count;
  if (c == null || d.type == DecisionType.motionDeCensure) return false;
  final exprimes = c.pour + c.contre;
  return exprimes > 0 &&
      (c.pour - c.contre).abs() <= exprimes * tightMarginRatio;
}

/// Configuration inhabituelle : unanimité des exprimés, ou un groupe
/// partagé (égalité entre ses positions les plus suivies).
bool isUnusualVote(DecisionDetail detail) {
  final d = detail.decision;
  final c = d.count;
  if (c != null && d.type != DecisionType.motionDeCensure) {
    final exprimes = c.pour + c.contre;
    if (exprimes > 0 && (c.pour == 0 || c.contre == 0)) return true;
  }
  return detail.groups.any((g) => g.position == GroupPosition.partage);
}

bool _hasArguments(DecisionDetail detail) {
  final a = detail.arguments;
  return a != null &&
      (a.pour.isNotEmpty || a.contre.isNotEmpty || a.abstention.isNotEmpty);
}

int _compare(DecisionDetail a, DecisionDetail b) {
  int flag(bool x) => x ? 0 : 1;
  final da = a.decision;
  final db = b.decision;
  for (final c in [
    postPriority(da).compareTo(postPriority(db)),
    flag(isTightVote(da)).compareTo(flag(isTightVote(db))),
    flag(isUnusualVote(a)).compareTo(flag(isUnusualVote(b))),
    flag(_hasArguments(a)).compareTo(flag(_hasArguments(b))),
    db.date.compareTo(da.date),
    (db.numero ?? 0).compareTo(da.numero ?? 0),
    da.id.compareTo(db.id),
  ]) {
    if (c != 0) return c;
  }
  return 0;
}
