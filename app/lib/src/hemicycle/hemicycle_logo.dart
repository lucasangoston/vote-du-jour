import 'package:flutter/material.dart';

import '../theme.dart';
import 'vote_arc.dart';

/// Logo « Hémicycle » : rangées de points en demi-cercle, les sièges de
/// l'hémicycle. Dessiné dans la boîte de 120 × 66 unités des maquettes.
class HemicycleLogo extends StatelessWidget {
  /// Logo de l'en-tête de la liste : deux rangées, gros points (30 × 17).
  const HemicycleLogo.small({super.key, this.width = 30, this.color})
    : rows = const [54, 34],
      dot = 9,
      spacing = 13;

  /// Logo de la planche d'identité : trois rangées, points fins.
  const HemicycleLogo.large({super.key, this.width = 120, this.color})
    : rows = const [54, 42, 30],
      dot = 5,
      spacing = 9.42;

  final double width;

  /// Couleur des points ; par défaut, l'encre du thème.
  final Color? color;

  /// Rayon de chaque rangée, diamètre des points et espacement, en unités.
  final List<double> rows;
  final double dot;
  final double spacing;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size(width, width * VoteArc.aspect),
      painter: _LogoPainter(
        rows: rows,
        dot: dot,
        spacing: spacing,
        color: color ?? context.colors.ink,
      ),
    ),
  );
}

class _LogoPainter extends CustomPainter {
  _LogoPainter({
    required this.rows,
    required this.dot,
    required this.spacing,
    required this.color,
  });

  final List<double> rows;
  final double dot;
  final double spacing;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 120;
    for (final radius in rows) {
      paintDottedArc(
        canvas,
        center: Offset(60 * unit, 60 * unit),
        radius: radius * unit,
        dot: dot * unit,
        spacing: spacing * unit,
        color: color,
      );
    }
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.color != color || old.dot != dot || old.spacing != spacing;
}
