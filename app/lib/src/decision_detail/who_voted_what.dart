import 'package:flutter/material.dart';
import 'package:vote_contract/vote_contract.dart';

import '../hemicycle/vote_glyph.dart';
import '../theme.dart';
import 'group_logo.dart';
import 'group_ranking.dart';

/// Intertitre du vote par groupe politique.
const groupsHeading = 'Qui a voté quoi';

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
/// vignette (logo, sigle, voix), rangé selon sa position. Une position sans
/// groupe n'a pas de rangée ; la règle de classement est expliquée dans
/// « À propos ».
///
/// Avec [onSelect] (détail aux places réelles, #74), chaque vignette est un
/// bouton qui allume les sièges de son groupe dans l'hémicycle ; [selected]
/// est la référence du groupe allumé.
class WhoVotedWhat extends StatelessWidget {
  const WhoVotedWhat(this.groups, {super.key, this.selected, this.onSelect});

  final List<GroupVoteDetail> groups;
  final String? selected;
  final ValueChanged<GroupVoteDetail>? onSelect;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, row) in rankGroups(groups).indexed) ...[
        if (i > 0) const SizedBox(height: 22),
        _RowHeader(row.position),
        const SizedBox(height: 10),
        _TileGrid(row.groups, selected: selected, onSelect: onSelect),
      ],
    ],
  );
}

class _RowHeader extends StatelessWidget {
  const _RowHeader(this.position);

  final GroupPosition position;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Le symbole du vote, celui des sièges et de la légende (#74).
    final (glyph, color) = switch (position) {
      GroupPosition.pour => (VotePosition.pour, colors.pour),
      GroupPosition.contre => (VotePosition.contre, colors.contre),
      GroupPosition.abstention => (VotePosition.abstention, colors.ink2),
      GroupPosition.partage || GroupPosition.nonVotant => (null, colors.ink2),
    };
    return Semantics(
      header: true,
      child: Row(
        children: [
          if (glyph != null) ...[
            VoteGlyph(glyph, color: color),
            const SizedBox(width: 8),
          ],
          Text(
            groupRowLabel(position),
            style: HemicycleText.labelStrong.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// Grille de trois vignettes par ligne, de même hauteur sur une ligne.
class _TileGrid extends StatelessWidget {
  const _TileGrid(this.groups, {this.selected, this.onSelect});

  final List<GroupVoteDetail> groups;
  final String? selected;
  final ValueChanged<GroupVoteDetail>? onSelect;

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
                        ? GroupTile(
                            groups[i],
                            selected: groups[i].organeRef == selected,
                            onTap: onSelect == null
                                ? null
                                : () => onSelect!(groups[i]),
                          )
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

/// Libellé d'une vignette bouton (#74) : « RN, pour, montrer ses sièges ».
String groupTileButtonLabel(GroupVoteDetail group) =>
    '${groupCaption(group)}, '
    '${groupPositionLabel(group.position).toLowerCase()}, '
    'montrer ses sièges';

/// Vignette d'un groupe, à angle droit : logo (ou sigle sur fond graphite)
/// et légende. Avec [onTap], un bouton ; choisie ([selected]), elle prend un
/// fond relevé et un bord intérieur plein de 2 points : l'état ne tient pas
/// à une nuance.
class GroupTile extends StatelessWidget {
  const GroupTile(this.group, {super.key, this.selected = false, this.onTap});

  final GroupVoteDetail group;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final c = group.count;
    final content = Container(
      padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
      // Le bord en avant-plan ne décale pas le contenu.
      foregroundDecoration: selected
          ? BoxDecoration(border: Border.all(color: colors.ink, width: 2))
          : null,
      child: Column(
        children: [
          _Logo(group),
          const SizedBox(height: 6),
          Text(
            groupCaption(group),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: HemicycleText.caption.copyWith(color: colors.ink),
          ),
        ],
      ),
    );
    final background = selected ? colors.raised : colors.surface;
    if (onTap == null) {
      return Semantics(
        container: true,
        label:
            '${group.name} : ${groupPositionLabel(group.position)}, '
            '${c.pour} pour, ${c.contre} contre, ${c.abstentions} abstentions',
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(color: background),
          child: content,
        ),
      );
    }
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: groupTileButtonLabel(group),
      excludeSemantics: true,
      child: Material(
        color: background,
        child: InkWell(onTap: onTap, child: content),
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final asset = groupLogoAsset(group);
    if (asset == null) {
      return Container(
        width: 44,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        color: colors.mark,
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            groupMark(group),
            style: HemicycleText.mark.copyWith(
              fontSize: 13,
              color: colors.onMark,
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
      color: colors.plate,
      child: image,
    );
  }
}
