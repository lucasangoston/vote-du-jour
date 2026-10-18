import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Logo Perchoir, « hémicycle en bandes » (#36) : deux arcs épais concentriques
/// et un demi-disque plein au centre, le perchoir.
///
/// Géométrie de la grille de 120 des maquettes : centre (60, 86), arcs de
/// rayon 46 et 28, bouts droits ; demi-disque de rayon égal à l'épaisseur. Le
/// cadre est celui des maquettes (viewBox `8 34 104 58`). L'épaisseur grossit
/// un peu aux petites tailles pour rester lisible (12 en grand, 13 dans
/// l'en-tête de la liste, 14 dans les widgets).
class HemicycleLogo extends StatelessWidget {
  /// Logo de l'en-tête de la liste (30 × 17).
  const HemicycleLogo.small({super.key, this.width = 30, this.color})
    : weight = 13;

  /// Logo de la planche d'identité et de « À propos ».
  const HemicycleLogo.large({super.key, this.width = 120, this.color})
    : weight = 12;

  /// Rapport hauteur / largeur du cadre (104 × 58 unités).
  static const aspect = 58 / 104;

  final double width;

  /// Couleur des arcs ; par défaut, l'encre du thème. Le demi-disque prend
  /// toujours la couleur du pour (adopté).
  final Color? color;

  /// Épaisseur des arcs et rayon du demi-disque, en unités de la grille.
  final double weight;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size(width, width * aspect),
      painter: HemicycleLogoPainter(
        weight: weight,
        arcs: color ?? context.colors.ink,
        seat: context.colors.pour,
      ),
    ),
  );
}

/// Dessin du logo dans un cadre de rapport [HemicycleLogo.aspect].
class HemicycleLogoPainter extends CustomPainter {
  HemicycleLogoPainter({
    required this.weight,
    required this.arcs,
    required this.seat,
  });

  final double weight;
  final Color arcs;
  final Color seat;

  static const _center = Offset(60, 86);
  static const _radii = [46.0, 28.0];

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 104;
    canvas
      ..save()
      ..scale(unit)
      ..translate(-8, -34);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = weight
      ..strokeCap = StrokeCap.butt
      ..color = arcs;
    for (final radius in _radii) {
      canvas.drawArc(
        Rect.fromCircle(center: _center, radius: radius),
        math.pi,
        math.pi,
        false,
        stroke,
      );
    }
    canvas
      ..drawArc(
        Rect.fromCircle(center: _center, radius: weight),
        math.pi,
        math.pi,
        true,
        Paint()..color = seat,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(HemicycleLogoPainter old) =>
      old.weight != weight || old.arcs != arcs || old.seat != seat;
}
