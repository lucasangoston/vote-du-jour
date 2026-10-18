import 'package:flutter/material.dart';
import 'package:vote_contract/vote_contract.dart';

import '../theme.dart';

/// Barre segmentée du vote d'un groupe : pour, abstentions puis contre (même
/// ordre que l'arc), proportionnelle aux votants, sans piste de fond. Les
/// non-votants n'y figurent pas.
///
/// Mêmes teintes que l'arc : vert pour, brique contre, gris abstentions,
/// aucune couleur de parti.
class VoteBar extends StatelessWidget {
  const VoteBar(this.count, {super.key, this.height = 6});

  final VoteCount count;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final segments = [
      (count.pour, colors.pour),
      (count.abstentions, colors.abstention),
      (count.contre, colors.contre),
    ].where((s) => s.$1 > 0).toList();
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (final (i, (value, color)) in segments.indexed)
            Expanded(
              flex: value,
              child: Container(
                margin: EdgeInsets.only(left: i == 0 ? 0 : 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
