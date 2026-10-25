import 'package:flutter/material.dart';

import 'hemicycle/hemicycle_seats.dart';
import 'theme.dart';

/// Bloc gris à angle droit qui tient la place d'un contenu en chargement.
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    this.width,
    required this.height,
    this.color,
  });

  final double? width;
  final double height;

  /// Teinte du bloc ; par défaut la surface relevée du thème.
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: ColoredBox(color: color ?? context.colors.raised),
  );
}

/// Squelette de l'écran de détail pendant le chargement du fichier de
/// détail : la carte du vote, le titre, l'explication et la grille des
/// groupes, à leur place. Rien ne s'affiche à moitié (l'ancien arc puis
/// l'hémicycle) : l'écran passe d'un coup du squelette au contenu.
class DetailSkeleton extends StatelessWidget {
  const DetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: 'Chargement de la décision',
      container: true,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final figure = width < 376 ? width - 36 : 340.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              // Carte du vote : hémicycle, résultat, trois chiffres.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
                color: colors.surface,
                child: Column(
                  children: [
                    SkeletonBlock(
                      width: figure,
                      height: figure * HemicycleSeats.aspect,
                    ),
                    const SizedBox(height: 18),
                    const SkeletonBlock(width: 140, height: 30),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          const Expanded(
                            child: Column(
                              children: [
                                SkeletonBlock(width: 52, height: 26),
                                SizedBox(height: 8),
                                SkeletonBlock(width: 72, height: 12),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const SkeletonBlock(width: 220, height: 12),
              const SizedBox(height: 14),
              SkeletonBlock(width: width * 0.9, height: 30),
              const SizedBox(height: 8),
              SkeletonBlock(width: width * 0.6, height: 30),
              const SizedBox(height: 18),
              for (final f in const [1.0, 0.95, 0.9, 0.5]) ...[
                SkeletonBlock(width: width * f, height: 16),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 22),
              const SkeletonBlock(width: 180, height: 24),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.1,
                children: List.filled(
                  6,
                  SkeletonBlock(height: 100, color: colors.surface),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
