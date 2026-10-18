import 'dart:convert';

import 'package:vote_contract/vote_contract.dart';

import 'group_directory.dart';
import 'index_builder.dart';
import 'object_store.dart';
import 'scrutin.dart';

/// Cache HTTP des fichiers de détail : court, comme l'index (une décision
/// provisoire peut être confirmée ou complétée).
const detailCacheControl = 'public, max-age=300';

/// Construit le fichier de détail de chaque décision de [index] à partir du
/// scrutin correspondant dans [scrutins]. Une décision sans scrutin (texte
/// adopté à main levée) a un détail sans décompte ni vote par groupe.
///
/// [groups] donne le nom des groupes ; sans lui, ou pour un groupe inconnu,
/// le nom est [unknownGroupName].
List<DecisionDetail> buildDecisionDetails(
  Iterable<Scrutin> scrutins,
  DecisionIndex index, {
  GroupDirectory? groups,
}) {
  final byUid = {for (final s in scrutins) s.uid: s};
  return [
    for (final d in index.decisions)
      buildDecisionDetail(d, scrutin: byUid[d.id], groups: groups),
  ];
}

/// Détails des décisions provisoires de [index] (détection en direct, #10)
/// à partir des scrutins lus sur le site ([provisional]) : décompte du site,
/// sans vote par groupe, que le site ne donne pas. Les détails des décisions
/// confirmées ne sont pas reconstruits : le passage en direct n'a pas les
/// votes par groupe du jeu de données.
List<DecisionDetail> buildProvisionalDetails(
  Iterable<Scrutin> provisional,
  DecisionIndex index,
) {
  final byUid = {for (final s in provisional) s.uid: s};
  return [
    for (final d in index.decisions)
      if (d.status == DecisionStatus.provisoire)
        if (byUid[d.id] case final scrutin?)
          buildDecisionDetail(d, scrutin: scrutin),
  ];
}

/// Détail d'une décision : [decision] (champs de l'index), plus le décompte
/// et le vote par groupe de son [scrutin].
DecisionDetail buildDecisionDetail(
  DecisionSummary decision, {
  Scrutin? scrutin,
  GroupDirectory? groups,
}) {
  if (scrutin == null) return DecisionDetail(decision: decision);
  return DecisionDetail(
    decision: decision,
    count: voteCountOf(scrutin.decompte),
    groups: [
      for (final g in scrutin.groupVotes)
        GroupVoteDetail(
          organeRef: g.organeRef,
          name: groups?[g.organeRef]?.name ?? unknownGroupName,
          abbreviation: groups?[g.organeRef]?.abbreviation,
          // Calculée sur le décompte : `positionMajoritaire` vaut « pour »
          // quand aucun membre n'a voté.
          position: GroupPosition.fromCount(voteCountOf(g.decompte)),
          count: voteCountOf(g.decompte),
        ),
    ],
  );
}

/// Contenu publié d'un fichier de détail.
String encodeDecisionDetail(DecisionDetail detail) =>
    const JsonEncoder.withIndent('  ').convert(detail.toJson());

/// Publie les fichiers de détail (`v1/decisions/<id>.json`) en ne réécrivant
/// que ceux dont le contenu a changé : chaque fichier est comparé à la
/// version déjà publiée. Renvoie le nombre de fichiers écrits.
///
/// Les fichiers des décisions sorties de l'index sont laissés en place : une
/// app qui affiche encore un ancien index peut les ouvrir.
Future<int> publishDecisionDetails(
  ObjectStore store,
  Iterable<DecisionDetail> details,
) async {
  var written = 0;
  for (final detail in details) {
    final key = decisionDetailPath(detail.decision.id);
    final body = encodeDecisionDetail(detail);
    if (await store.read(key) == body) continue;
    await store.write(key, body, cacheControl: detailCacheControl);
    written++;
  }
  return written;
}
