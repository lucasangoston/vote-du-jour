import 'package:flutter/material.dart';
import 'package:vote_contract/vote_contract.dart';

import '../theme.dart';
import 'line_icon.dart';

/// Mot du résultat (« Adopté » / « Rejeté »).
String resultWord(VoteResult result) => switch (result) {
  VoteResult.adopte => 'Adopté',
  VoteResult.rejete => 'Rejeté',
};

/// Couleur du résultat : celle du pour (adopté) ou du contre (rejeté).
Color resultColor(BuildContext context, VoteResult result) => switch (result) {
  VoteResult.adopte => context.colors.pour,
  VoteResult.rejete => context.colors.contre,
};

/// Coche ou croix du résultat.
LineGlyph resultGlyph(VoteResult result) => switch (result) {
  VoteResult.adopte => LineGlyph.check,
  VoteResult.rejete => LineGlyph.cross,
};

/// Ligne de méta des maquettes : éléments séparés par « · », qui passent à
/// la ligne au besoin.
class MetaLine extends StatelessWidget {
  const MetaLine({
    super.key,
    required this.parts,
    required this.style,
    this.trailing,
  });

  final List<Widget> parts;
  final TextStyle style;

  /// Élément ajouté après les autres, sans séparateur (badge provisoire).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: style,
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 2,
      children: [
        for (final (i, part) in parts.indexed) ...[
          if (i > 0) const Text(' · '),
          part,
        ],
        if (trailing case final trailing?) ...[
          const SizedBox(width: 8),
          trailing,
        ],
      ],
    ),
  );
}
