import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Rubriques de l'accueil : chacune garde la même couleur et le même
/// pictogramme sur toutes ses cartes, pour qu'on la reconnaisse avant de
/// lire. Aucune couleur de rubrique n'est le vert « pour » ni la rouille
/// « contre » : le résultat garde les siennes.
enum Rubric {
  enDebat('En débat'),
  voteSolennel('Vote solennel'),
  decision('Décision');

  const Rubric(this.label);

  /// Nom de la rubrique, dans le bandeau de la carte.
  final String label;

  /// Couleur de la rubrique : bandeau et cadre de la carte.
  Color fill(Brightness b) => switch (this) {
    Rubric.enDebat => const Color(0xFFF2B233),
    Rubric.voteSolennel =>
      b == Brightness.dark ? const Color(0xFF6E8EF0) : const Color(0xFF2B4FC4),
    Rubric.decision =>
      b == Brightness.dark ? const Color(0xFFFFFFFF) : const Color(0xFF111111),
  };

  /// Texte et pictogramme posés sur [fill].
  Color onFill(Brightness b) => switch (this) {
    Rubric.enDebat => const Color(0xFF1A1300),
    Rubric.voteSolennel => const Color(0xFFFFFFFF),
    Rubric.decision =>
      b == Brightness.dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
  };

  /// Feuille de la carte : de jour, la surface légèrement teintée de
  /// [fill] ; de nuit, la surface seule (une teinte sur fond sombre voile la
  /// carte comme un filtre et éteint les sièges et les chiffres) : le
  /// bandeau et le cadre suffisent à reconnaître la rubrique.
  Color sheet(BuildContext context) {
    final b = Theme.of(context).brightness;
    if (b == Brightness.dark) return context.colors.surface;
    return Color.lerp(context.colors.surface, fill(b), 0.10)!;
  }
}

/// Pictogramme au trait d'une rubrique, dans une boîte de 24 × 24 unités :
/// bulle de parole (en débat), urne (vote solennel), hémicycle (décision).
class RubricGlyph extends StatelessWidget {
  const RubricGlyph(
    this.rubric, {
    super.key,
    required this.color,
    this.size = 24,
  });

  final Rubric rubric;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _GlyphPainter(rubric, color),
    ),
  );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.rubric, this.color);

  final Rubric rubric;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    switch (rubric) {
      case Rubric.enDebat:
        canvas.drawPath(
          Path()
            ..moveTo(7, 17)
            ..lineTo(4, 21)
            ..lineTo(4, 17)
            ..addRRect(
              RRect.fromLTRBR(2.5, 3.5, 21.5, 17, const Radius.circular(3.5)),
            ),
          stroke,
        );
        for (final x in [7.5, 12.0, 16.5]) {
          canvas.drawCircle(Offset(x, 10.25), 1.4, fill);
        }
      case Rubric.voteSolennel:
        canvas.drawRRect(
          RRect.fromLTRBR(3, 11, 21, 21, const Radius.circular(1.5)),
          stroke,
        );
        canvas.drawLine(const Offset(8, 11), const Offset(16, 11), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(9, 11)
            ..lineTo(9, 3.5)
            ..lineTo(15, 3.5)
            ..lineTo(15, 11),
          stroke,
        );
      case Rubric.decision:
        for (final r in [9.0, 5.0]) {
          canvas.drawArc(
            Rect.fromCircle(center: const Offset(12, 18), radius: r),
            math.pi,
            math.pi,
            false,
            stroke,
          );
        }
        canvas.drawCircle(const Offset(12, 18), 1.6, fill);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.rubric != rubric || old.color != color;
}

/// Bandeau en tête d'une carte : pictogramme et nom de la rubrique, à droite
/// une précision ([detail], la date d'une décision).
class RubricBand extends StatelessWidget {
  const RubricBand(this.rubric, {super.key, this.detail});

  final Rubric rubric;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final on = rubric.onFill(b);
    return Container(
      color: rubric.fill(b),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Row(
        children: [
          RubricGlyph(rubric, color: on),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rubric.label,
              style: HemicycleText.labelStrong.copyWith(
                fontSize: 17,
                color: on,
              ),
            ),
          ),
          if (detail case final detail?)
            Text(detail, style: HemicycleText.metaStrong.copyWith(color: on)),
        ],
      ),
    );
  }
}
