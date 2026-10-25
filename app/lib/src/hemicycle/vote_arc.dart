import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vote_contract/vote_contract.dart';

import '../theme.dart';

/// Teinte d'un segment de l'arc.
enum ArcTone { pour, abstention, contre }

/// Portion de l'arc, de [start] à [end] (fractions du demi-cercle, de gauche
/// à droite).
@immutable
class ArcSegment {
  const ArcSegment(this.tone, this.start, this.end);

  final ArcTone tone;
  final double start;
  final double end;

  @override
  bool operator ==(Object other) =>
      other is ArcSegment &&
      other.tone == tone &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(tone, start, end);

  @override
  String toString() => 'ArcSegment($tone, $start, $end)';
}

/// Ce que dessine l'arc du vote : des segments pleins, ou un seul arc en
/// pointillés ronds ([dotted]).
@immutable
class VoteArcPlan {
  const VoteArcPlan(this.segments, {this.dotted = false});

  final List<ArcSegment> segments;
  final bool dotted;

  /// Règles de la charte (#29, #67) :
  ///
  /// - scrutin public avec arc dans l'ordre de l'hémicycle ([arc]) : les
  ///   tronçons de gauche à droite, groupes de gauche à gauche, chacun
  ///   proportionnel à ses voix ;
  /// - scrutin public avec décompte seulement (décision provisoire, index
  ///   ancien) : demi-cercle rempli de gauche à droite, pour puis abstentions
  ///   puis contre, proportionnel à pour + contre + abstentions ;
  /// - vote à main levée : arc en pointillés ronds, couleur du résultat ;
  /// - sans décompte (index ancien, décompte vide) : arc plein, couleur du
  ///   résultat.
  factory VoteArcPlan.of({
    required VoteResult result,
    VoteTally? count,
    VoteMode? voteMode,
    List<HemicycleSegment>? arc,
  }) {
    final tone = switch (result) {
      VoteResult.adopte => ArcTone.pour,
      VoteResult.rejete => ArcTone.contre,
    };
    if (voteMode == VoteMode.mainLevee) {
      return VoteArcPlan([ArcSegment(tone, 0, 1)], dotted: true);
    }
    final arcTotal = arc?.fold(0, (total, s) => total + s.n) ?? 0;
    if (arc != null && arcTotal > 0) {
      final segments = <ArcSegment>[];
      var votes = 0;
      for (final s in arc) {
        final start = votes / arcTotal;
        votes += s.n;
        final tone = switch (s.position) {
          ArcPosition.pour => ArcTone.pour,
          ArcPosition.abstention => ArcTone.abstention,
          ArcPosition.contre => ArcTone.contre,
        };
        segments.add(ArcSegment(tone, start, votes / arcTotal));
      }
      return VoteArcPlan(segments);
    }
    if (count == null || count.total <= 0) {
      return VoteArcPlan([ArcSegment(tone, 0, 1)]);
    }
    final total = count.total;
    final pour = count.pour / total;
    final abstentions = (count.pour + count.abstentions) / total;
    return VoteArcPlan([
      if (count.pour > 0) ArcSegment(ArcTone.pour, 0, pour),
      if (count.abstentions > 0)
        ArcSegment(ArcTone.abstention, pour, abstentions),
      if (count.contre > 0) ArcSegment(ArcTone.contre, abstentions, 1),
    ]);
  }
}

/// L'arc du vote, signature de la charte : un demi-cercle dessiné dans une
/// boîte de 120 × 66 unités (celle des maquettes), mise à l'échelle de
/// [width].
class VoteArc extends StatelessWidget {
  const VoteArc({
    super.key,
    required this.result,
    this.count,
    this.voteMode,
    this.arc,
    this.width = 280,
    this.radius = 52,
    this.stroke = 9,
  });

  final VoteResult result;
  final VoteTally? count;
  final VoteMode? voteMode;

  /// Arc dans l'ordre de l'hémicycle (#67), s'il est publié.
  final List<HemicycleSegment>? arc;

  /// Largeur en points ; la hauteur suit (66 / 120).
  final double width;

  /// Rayon et épaisseur du trait, en unités de la boîte de 120.
  final double radius;
  final double stroke;

  /// Rapport hauteur / largeur de la boîte.
  static const aspect = 66 / 120;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final plan = VoteArcPlan.of(
      result: result,
      count: count,
      voteMode: voteMode,
      arc: arc,
    );
    return Semantics(
      container: true,
      label: voteArcLabel(result: result, count: count, voteMode: voteMode),
      child: CustomPaint(
        size: Size(width, width * aspect),
        painter: VoteArcPainter(
          plan: plan,
          radius: radius,
          stroke: stroke,
          colorOf: (tone) => switch (tone) {
            ArcTone.pour => colors.pour,
            ArcTone.abstention => colors.abstention,
            ArcTone.contre => colors.contre,
          },
        ),
      ),
    );
  }
}

/// Part du camp gagnant parmi les votants (#75) : pour / votants si adopté,
/// contre / votants si rejeté. Main levée ou sans décompte : 1, jauge pleine.
double gaugeShare({
  required VoteResult result,
  VoteTally? count,
  VoteMode? voteMode,
}) {
  if (voteMode == VoteMode.mainLevee || count == null || count.total <= 0) {
    return 1;
  }
  final won = switch (result) {
    VoteResult.adopte => count.pour,
    VoteResult.rejete => count.contre,
  };
  // Camp gagnant minoritaire (censure, rejet préalable, majorité spéciale) : jauge pleine.
  if (won * 2 <= count.total) return 1;
  return won / count.total;
}

/// Jauge des lignes de la liste (#75), 40 × 22 : le petit arc d'une seule
/// couleur, rempli de gauche à droite de la part du camp gagnant (vert si
/// adopté, rouge si rejeté), le reste de l'arc en teinte neutre.
class VoteGauge extends StatelessWidget {
  const VoteGauge({super.key, required this.result, this.count, this.voteMode});

  final VoteResult result;
  final VoteTally? count;
  final VoteMode? voteMode;

  /// Largeur en points ; la hauteur suit ([VoteArc.aspect]).
  static const width = 40.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      container: true,
      label: voteArcLabel(result: result, count: count, voteMode: voteMode),
      child: CustomPaint(
        size: const Size(width, width * VoteArc.aspect),
        painter: VoteGaugePainter(
          share: gaugeShare(result: result, count: count, voteMode: voteMode),
          color: switch (result) {
            VoteResult.adopte => colors.pour,
            VoteResult.rejete => colors.contre,
          },
          track: gaugeTrack(colors),
        ),
      ),
    );
  }
}

/// Teinte neutre du reste de la jauge : l'encre à 30 % sur la surface.
Color gaugeTrack(HemicycleColors colors) =>
    Color.lerp(colors.surface, colors.ink, 0.3)!;

/// Dessine la jauge dans la boîte de 120 × 66 unités des maquettes (rayon 50,
/// trait de 16).
class VoteGaugePainter extends CustomPainter {
  VoteGaugePainter({
    required this.share,
    required this.color,
    required this.track,
  });

  /// Part remplie, de 0 à 1.
  final double share;
  final Color color;
  final Color track;

  static const radius = 50.0;
  static const stroke = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 120;
    final rect = Rect.fromCircle(
      center: Offset(60 * unit, 60 * unit),
      radius: radius * unit,
    );
    Paint paintOf(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * unit
      ..strokeCap = StrokeCap.butt
      ..color = c;
    // Comme les maquettes : pas de reste visible à 100 % (arrondi compris).
    if (share >= 0.999) {
      canvas.drawArc(rect, math.pi, math.pi, false, paintOf(color));
      return;
    }
    canvas.drawArc(rect, math.pi, math.pi, false, paintOf(track));
    if (share > 0) {
      canvas.drawArc(rect, math.pi, share * math.pi, false, paintOf(color));
    }
  }

  @override
  bool shouldRepaint(VoteGaugePainter old) =>
      old.share != share || old.color != color || old.track != track;
}

/// Description de l'arc pour les lecteurs d'écran.
String voteArcLabel({
  required VoteResult result,
  VoteTally? count,
  VoteMode? voteMode,
}) {
  final word = switch (result) {
    VoteResult.adopte => 'Adopté',
    VoteResult.rejete => 'Rejeté',
  };
  if (voteMode == VoteMode.mainLevee) return '$word à main levée';
  if (count == null || count.total <= 0) return word;
  return '$word : ${count.pour} pour, ${count.contre} contre, '
      '${count.abstentions} abstentions';
}

class VoteArcPainter extends CustomPainter {
  VoteArcPainter({
    required this.plan,
    required this.radius,
    required this.stroke,
    required this.colorOf,
  });

  final VoteArcPlan plan;
  final double radius;
  final double stroke;
  final Color Function(ArcTone) colorOf;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 120;
    final center = Offset(60 * unit, 60 * unit);
    final r = radius * unit;
    if (plan.dotted) {
      // Pointillés ronds : points de 65 % de l'épaisseur, espacés d'une fois
      // et demie leur diamètre, répartis pour tomber sur les deux extrémités.
      final dot = stroke * 0.65 * unit;
      paintDottedArc(
        canvas,
        center: center,
        radius: r,
        dot: dot,
        spacing: dot * 1.5,
        color: colorOf(plan.segments.single.tone),
      );
      return;
    }
    final rect = Rect.fromCircle(center: center, radius: r);
    for (final s in plan.segments) {
      canvas.drawArc(
        rect,
        math.pi + s.start * math.pi,
        (s.end - s.start) * math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * unit
          ..strokeCap = StrokeCap.butt
          ..color = colorOf(s.tone),
      );
    }
  }

  @override
  bool shouldRepaint(VoteArcPainter old) =>
      old.plan.dotted != plan.dotted ||
      !_sameSegments(old.plan.segments, plan.segments) ||
      old.radius != radius ||
      old.stroke != stroke ||
      ArcTone.values.any((t) => old.colorOf(t) != colorOf(t));

  static bool _sameSegments(List<ArcSegment> a, List<ArcSegment> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);
}

/// Points ronds de diamètre [dot] le long du demi-cercle supérieur de centre
/// [center], de l'extrémité gauche à l'extrémité droite.
void paintDottedArc(
  Canvas canvas, {
  required Offset center,
  required double radius,
  required double dot,
  required double spacing,
  required Color color,
}) {
  final length = math.pi * radius;
  final intervals = math.max(1, (length / spacing).round());
  final paint = Paint()..color = color;
  for (var i = 0; i <= intervals; i++) {
    final angle = math.pi + math.pi * i / intervals;
    canvas.drawCircle(
      center + Offset(math.cos(angle), math.sin(angle)) * radius,
      dot / 2,
      paint,
    );
  }
}
