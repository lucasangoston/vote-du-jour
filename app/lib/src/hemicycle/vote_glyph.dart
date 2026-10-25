import 'package:flutter/material.dart';

/// Symbole d'une position de vote (#76), d'après les maquettes : disque plein
/// pour le pour, anneau pour le contre, petit point pour l'abstention. La
/// forme distingue les positions sans dépendre de la couleur.
enum VotePosition { pour, contre, abstention }

/// Dessine le symbole de [position] dans un carré de [size] points (12 par
/// défaut, la grille des maquettes).
class VoteGlyph extends StatelessWidget {
  const VoteGlyph(
    this.position, {
    super.key,
    required this.color,
    this.size = 12,
  });

  final VotePosition position;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _VoteGlyphPainter(position, color),
    ),
  );
}

class _VoteGlyphPainter extends CustomPainter {
  _VoteGlyphPainter(this.position, this.color);

  final VotePosition position;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Unités de la grille de 12 des maquettes.
    final unit = size.width / 12;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    switch (position) {
      case VotePosition.pour:
        canvas.drawCircle(center, 5 * unit, paint);
      case VotePosition.contre:
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * unit;
        canvas.drawCircle(center, 4 * unit, paint);
      case VotePosition.abstention:
        canvas.drawCircle(center, 2.2 * unit, paint);
    }
  }

  @override
  bool shouldRepaint(_VoteGlyphPainter old) =>
      old.position != position || old.color != color;
}
