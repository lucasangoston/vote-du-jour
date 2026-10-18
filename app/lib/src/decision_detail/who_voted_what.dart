import 'package:flutter/material.dart';
import 'package:vote_contract/vote_contract.dart';

import '../hemicycle/line_icon.dart';
import '../theme.dart';
import 'group_logo.dart';
import 'group_ranking.dart';

/// Intertitre du vote par groupe politique.
const groupsHeading = 'Qui a voté quoi';

/// Note sous la section.
const groupsNote =
    'Groupes classés selon la position de la majorité de leurs membres.';

/// Rangée vide parmi Pour, Contre et Abstention.
const noGroupLabel = 'Aucun groupe';

/// Libellé d'une rangée de groupes.
String groupRowLabel(GroupPosition position) => switch (position) {
  GroupPosition.pour => 'Pour',
  GroupPosition.contre => 'Contre',
  GroupPosition.abstention => 'Abstention',
  GroupPosition.partage => 'Partagé',
  GroupPosition.nonVotant => 'N\'ont pas voté',
};

/// Libellé de la position d'un groupe (lecteur d'écran).
String groupPositionLabel(GroupPosition position) => switch (position) {
  GroupPosition.pour => 'Pour',
  GroupPosition.contre => 'Contre',
  GroupPosition.abstention => 'Abstention',
  GroupPosition.partage => 'Partagé',
  GroupPosition.nonVotant => 'N\'a pas voté',
};

/// Rangées de « Qui a voté quoi » (sans l'intertitre) : chaque groupe en
/// vignette (logo, sigle, voix), rangé selon sa position, puis la note.
class WhoVotedWhat extends StatelessWidget {
  const WhoVotedWhat(this.groups, {super.key});

  final List<GroupVoteDetail> groups;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final row in rankGroups(groups)) ...[
        _RowHeader(row.position),
        const SizedBox(height: 10),
        if (row.groups.isEmpty) const _EmptyRow() else _TileGrid(row.groups),
        const SizedBox(height: 22),
      ],
      Text(
        groupsNote,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.5,
          color: context.colors.ink2,
        ),
      ),
    ],
  );
}

class _RowHeader extends StatelessWidget {
  const _RowHeader(this.position);

  final GroupPosition position;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (glyph, color) = switch (position) {
      GroupPosition.pour => (LineGlyph.check, colors.pour),
      GroupPosition.contre => (LineGlyph.cross, colors.contre),
      GroupPosition.abstention => (LineGlyph.dash, colors.ink2),
      GroupPosition.partage || GroupPosition.nonVotant => (null, colors.ink2),
    };
    return Semantics(
      header: true,
      child: Row(
        children: [
          if (glyph != null) ...[
            LineIcon(glyph, size: 18, strokeWidth: 2.4, color: color),
            const SizedBox(width: 8),
          ],
          Text(
            groupRowLabel(position),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      noGroupLabel,
      style: TextStyle(fontSize: 14, color: context.colors.ink2),
    ),
  );
}

/// Grille de trois vignettes par ligne, de même hauteur sur une ligne.
class _TileGrid extends StatelessWidget {
  const _TileGrid(this.groups);

  final List<GroupVoteDetail> groups;

  static const _columns = 3;
  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var start = 0; start < groups.length; start += _columns)
        Padding(
          padding: EdgeInsets.only(top: start == 0 ? 0 : _gap),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = start; i < start + _columns; i++) ...[
                  if (i > start) const SizedBox(width: _gap),
                  Expanded(
                    child: i < groups.length
                        ? GroupTile(groups[i])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ),
    ],
  );
}

/// Vignette d'un groupe : logo (ou sigle sur fond graphite), légende,
/// voix de sa position.
class GroupTile extends StatelessWidget {
  const GroupTile(this.group, {super.key});

  final GroupVoteDetail group;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final c = group.count;
    final figure = groupFigure(group);
    return Semantics(
      container: true,
      label:
          '${group.name} : ${groupPositionLabel(group.position)}, '
          '${c.pour} pour, ${c.contre} contre, ${c.abstentions} abstentions',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            _Logo(group),
            const SizedBox(height: 6),
            Text(
              groupCaption(group),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: colors.ink,
              ),
            ),
            if (figure != null) ...[
              const SizedBox(height: 4),
              Text(
                figure,
                textAlign: TextAlign.center,
                style: HemicycleText.mono.copyWith(
                  fontSize: 12,
                  height: 1.3,
                  color: colors.ink2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Logo du groupe dans une boîte de 72 × 44, ou vignette à sigle. En
/// sombre, le logo est posé sur une plaque claire : la plupart sont dessinés
/// pour un fond blanc.
class _Logo extends StatelessWidget {
  const _Logo(this.group);

  final GroupVoteDetail group;

  static const _graphite = Color(0xFF4F5761);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final asset = groupLogoAsset(group);
    if (asset == null) {
      return Container(
        width: 44,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: dark ? HemicycleColors.dark.abstention : _graphite,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            groupMark(group),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFFFFFFF),
            ),
          ),
        ),
      );
    }
    final image = Image.asset(
      asset,
      width: 72,
      height: 44,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
    if (!dark) return image;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: HemicycleColors.light.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: image,
    );
  }
}
