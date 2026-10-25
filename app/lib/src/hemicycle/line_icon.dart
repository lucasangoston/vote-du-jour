import 'package:flutter/material.dart';

import '../theme.dart';

/// Pictogramme au trait des maquettes, dans une boîte de 24 × 24 unités.
@immutable
class LineGlyph {
  const LineGlyph({
    this.lines = const [],
    this.circles = const [],
    this.dots = const [],
    this.join = StrokeJoin.round,
  });

  /// Lignes brisées (points successifs).
  final List<List<Offset>> lines;

  /// Cercles (centre, rayon), au trait.
  final List<(Offset, double)> circles;

  /// Points pleins (centre) du diamètre du trait.
  final List<Offset> dots;

  final StrokeJoin join;

  /// Coche de « Adopté ».
  static const check = LineGlyph(
    lines: [
      [Offset(5, 12.5), Offset(9.5, 17), Offset(19, 7.5)],
    ],
  );

  /// Croix de « Rejeté ».
  static const cross = LineGlyph(
    lines: [
      [Offset(6.5, 6.5), Offset(17.5, 17.5)],
      [Offset(17.5, 6.5), Offset(6.5, 17.5)],
    ],
  );

  /// Trait de « Abstention ».
  static const dash = LineGlyph(
    lines: [
      [Offset(6, 12), Offset(18, 12)],
    ],
  );

  /// Retour.
  static const back = LineGlyph(
    lines: [
      [Offset(15, 5), Offset(8, 12), Offset(15, 19)],
    ],
  );

  /// Ouvre un écran de l'app (« Ajouter le widget »).
  static const chevron = LineGlyph(
    lines: [
      [Offset(9.5, 6), Offset(15.5, 12), Offset(9.5, 18)],
    ],
  );

  /// Lien externe.
  static const external = LineGlyph(
    lines: [
      [Offset(8, 16), Offset(16, 8)],
      [Offset(9.5, 8), Offset(16, 8), Offset(16, 14.5)],
    ],
  );

  /// Ajouter le widget : trois carrés et un plus.
  static const widgets = LineGlyph(
    lines: [
      [
        Offset(4, 4),
        Offset(10.5, 4),
        Offset(10.5, 10.5),
        Offset(4, 10.5),
        Offset(4, 4),
      ],
      [
        Offset(13.5, 4),
        Offset(20, 4),
        Offset(20, 10.5),
        Offset(13.5, 10.5),
        Offset(13.5, 4),
      ],
      [
        Offset(4, 13.5),
        Offset(10.5, 13.5),
        Offset(10.5, 20),
        Offset(4, 20),
        Offset(4, 13.5),
      ],
      [Offset(16.75, 13.5), Offset(16.75, 20)],
      [Offset(13.5, 16.75), Offset(20, 16.75)],
    ],
  );

  /// À propos : un i cerclé.
  static const info = LineGlyph(
    circles: [(Offset(12, 12), 8.5)],
    lines: [
      [Offset(12, 11), Offset(12, 16.5)],
    ],
    dots: [Offset(12, 8)],
  );
}

/// Dessine un [LineGlyph] de [size] points, trait de [strokeWidth] unités.
class LineIcon extends StatelessWidget {
  const LineIcon(
    this.glyph, {
    super.key,
    this.size = 22,
    this.strokeWidth = 1.6,
    this.color,
  });

  final LineGlyph glyph;
  final double size;
  final double strokeWidth;

  /// Par défaut, l'encre du thème.
  final Color? color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _LineIconPainter(
        glyph,
        strokeWidth,
        color ?? context.colors.ink,
      ),
    ),
  );
}

class _LineIconPainter extends CustomPainter {
  _LineIconPainter(this.glyph, this.strokeWidth, this.color);

  final LineGlyph glyph;
  final double strokeWidth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 24;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * unit
      ..strokeCap = StrokeCap.round
      ..strokeJoin = glyph.join
      ..color = color;
    for (final line in glyph.lines) {
      final path = Path()..moveTo(line.first.dx * unit, line.first.dy * unit);
      for (final p in line.skip(1)) {
        path.lineTo(p.dx * unit, p.dy * unit);
      }
      canvas.drawPath(path, paint);
    }
    for (final (center, radius) in glyph.circles) {
      canvas.drawCircle(center * unit, radius * unit, paint);
    }
    final fill = Paint()..color = color;
    for (final dot in glyph.dots) {
      canvas.drawCircle(dot * unit, strokeWidth * 0.6 * unit, fill);
    }
  }

  @override
  bool shouldRepaint(_LineIconPainter old) =>
      old.glyph != glyph ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

/// Bouton icône de 44 × 44 des maquettes (en-tête de liste, retour).
class LineIconButton extends StatelessWidget {
  const LineIconButton({
    super.key,
    required this.glyph,
    required this.tooltip,
    required this.onPressed,
    this.strokeWidth = 1.6,
  });

  final LineGlyph glyph;
  final String tooltip;
  final VoidCallback onPressed;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 44,
            child: Center(child: LineIcon(glyph, strokeWidth: strokeWidth)),
          ),
        ),
      ),
    ),
  );
}

/// Bouton retour des écrans secondaires, aligné sur la marge de 20 points
/// (le pictogramme déborde de 10 points à gauche, comme dans les maquettes).
class HemicycleBackButton extends StatelessWidget {
  const HemicycleBackButton({super.key});

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: const Offset(-10, 0),
    child: Align(
      alignment: Alignment.centerLeft,
      child: LineIconButton(
        glyph: LineGlyph.back,
        tooltip: 'Retour',
        strokeWidth: 1.8,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    ),
  );
}
