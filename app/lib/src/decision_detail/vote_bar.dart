import 'package:flutter/material.dart';
import 'package:vote_contract/vote_contract.dart';

import '../theme.dart';

/// Barre horizontale pour / contre / abstention, proportionnelle aux voix
/// exprimées et aux abstentions (les non-votants n'y figurent pas).
///
/// Mêmes teintes que les badges (vert pour, brique contre), gris neutre pour
/// les abstentions : aucune couleur de parti.
class VoteBar extends StatelessWidget {
  const VoteBar(this.count, {super.key, this.height = 12});

  final VoteCount count;
  final double height;

  static const pourColor = ResultColors.adopted;
  static const contreColor = ResultColors.rejected;

  static Color abstentionColor(BuildContext context) =>
      Theme.of(context).colorScheme.outline;

  @override
  Widget build(BuildContext context) {
    final empty = Theme.of(context).colorScheme.surfaceContainerHighest;
    final segments = [
      (count.pour, pourColor),
      (count.contre, contreColor),
      (count.abstentions, abstentionColor(context)),
    ].where((s) => s.$1 > 0).toList();
    return Semantics(
      label:
          '${count.pour} pour, ${count.contre} contre, '
          '${count.abstentions} abstentions',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: segments.isEmpty
              ? ColoredBox(color: empty)
              : Row(
                  children: [
                    for (final (i, (value, color)) in segments.indexed)
                      Expanded(
                        flex: value,
                        child: Container(
                          margin: EdgeInsets.only(left: i == 0 ? 0 : 1.5),
                          color: color,
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
