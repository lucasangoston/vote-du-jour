import 'package:vote_contract/vote_contract.dart';

/// Une rangée de « Qui a voté quoi » : les groupes d'une même position.
class GroupRow {
  const GroupRow(this.position, this.groups);

  final GroupPosition position;

  /// Groupes de la rangée, du plus grand nombre de voix au plus petit.
  final List<GroupVoteDetail> groups;
}

/// Classe les groupes selon leur position (celle de la majorité de leurs
/// membres) : rangées Pour, Contre, Abstention, Partagé et N'ont pas voté,
/// une rangée vide n'est pas affichée. Aucun groupe ne disparaît. Dans une rangée, les groupes vont du plus grand nombre de voix
/// de la position au plus petit ; à égalité, l'ordre du fichier est gardé.
List<GroupRow> rankGroups(List<GroupVoteDetail> groups) => [
  for (final position in GroupPosition.values)
    if (_rowOf(groups, position) case final row when row.isNotEmpty)
      GroupRow(position, row),
];

List<GroupVoteDetail> _rowOf(
  List<GroupVoteDetail> groups,
  GroupPosition position,
) {
  final row = [
    for (final (i, group) in groups.indexed)
      if (group.position == position) (i, group),
  ];
  row.sort((a, b) {
    final byVotes = positionVotes(b.$2).compareTo(positionVotes(a.$2));
    return byVotes != 0 ? byVotes : a.$1.compareTo(b.$1);
  });
  return [for (final (_, group) in row) group];
}

/// Nombre de voix du groupe pour sa position ; pour un groupe partagé, ses
/// votants ; zéro pour un groupe qui n'a pas voté.
int positionVotes(GroupVoteDetail group) {
  final c = group.count;
  return switch (group.position) {
    GroupPosition.pour => c.pour,
    GroupPosition.contre => c.contre,
    GroupPosition.abstention => c.abstentions,
    GroupPosition.partage => c.votants,
    GroupPosition.nonVotant => 0,
  };
}
