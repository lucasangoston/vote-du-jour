import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:votedujour/src/hemicycle/vote_arc.dart';
import 'package:votedujour/src/theme.dart';

void main() {
  group('règles de l\'arc (#29)', () {
    test('pour, abstentions puis contre, proportionnels aux votants', () {
      final plan = VoteArcPlan.of(
        result: VoteResult.rejete,
        count: const VoteTally(pour: 144, contre: 199, abstentions: 5),
      );
      expect(plan.dotted, isFalse);
      expect(plan.segments.map((s) => s.tone), [
        ArcTone.pour,
        ArcTone.abstention,
        ArcTone.contre,
      ]);
      expect(plan.segments.first.start, 0);
      expect(plan.segments[0].end, closeTo(144 / 348, 1e-9));
      expect(plan.segments[1].start, plan.segments[0].end);
      expect(plan.segments[1].end, closeTo(149 / 348, 1e-9));
      expect(plan.segments[2].start, plan.segments[1].end);
      expect(plan.segments.last.end, 1);
    });

    test('un segment vide n\'est pas dessiné', () {
      final plan = VoteArcPlan.of(
        result: VoteResult.adopte,
        count: const VoteTally(pour: 503, contre: 0, abstentions: 67),
      );
      expect(plan.segments, [
        const ArcSegment(ArcTone.pour, 0, 503 / 570),
        const ArcSegment(ArcTone.abstention, 503 / 570, 1),
      ]);
    });

    test("arc dans l'ordre de l'hémicycle (#67) : tronçons de gauche à "
        'droite, proportionnels aux voix', () {
      // Scrutin 8706 : LFI-NFP s'abstient, tout à gauche.
      final plan = VoteArcPlan.of(
        result: VoteResult.adopte,
        count: const VoteTally(pour: 503, contre: 0, abstentions: 67),
        arc: const [
          HemicycleSegment(ArcPosition.abstention, 66),
          HemicycleSegment(ArcPosition.pour, 382),
          HemicycleSegment(ArcPosition.abstention, 1),
          HemicycleSegment(ArcPosition.pour, 121),
        ],
      );
      expect(plan.dotted, isFalse);
      expect(plan.segments, [
        const ArcSegment(ArcTone.abstention, 0, 66 / 570),
        const ArcSegment(ArcTone.pour, 66 / 570, 448 / 570),
        const ArcSegment(ArcTone.abstention, 448 / 570, 449 / 570),
        const ArcSegment(ArcTone.pour, 449 / 570, 1),
      ]);
    });

    test("arc de l'hémicycle : rejeté, contre à gauche et pour à droite", () {
      final plan = VoteArcPlan.of(
        result: VoteResult.rejete,
        count: const VoteTally(pour: 151, contre: 187, abstentions: 0),
        arc: const [
          HemicycleSegment(ArcPosition.contre, 187),
          HemicycleSegment(ArcPosition.pour, 151),
        ],
      );
      expect(plan.segments.map((s) => s.tone), [ArcTone.contre, ArcTone.pour]);
      expect(plan.segments.last.end, 1);
    });

    test("main levée : l'arc de l'hémicycle éventuel est ignoré", () {
      final plan = VoteArcPlan.of(
        result: VoteResult.adopte,
        voteMode: VoteMode.mainLevee,
        arc: const [HemicycleSegment(ArcPosition.contre, 3)],
      );
      expect(plan.dotted, isTrue);
      expect(plan.segments, [const ArcSegment(ArcTone.pour, 0, 1)]);
    });

    test('main levée : pointillés de la couleur du résultat', () {
      final plan = VoteArcPlan.of(
        result: VoteResult.adopte,
        voteMode: VoteMode.mainLevee,
        // Un décompte éventuel est ignoré : il n'y en a pas à main levée.
        count: const VoteTally(pour: 1, contre: 0, abstentions: 0),
      );
      expect(plan.dotted, isTrue);
      expect(plan.segments, [const ArcSegment(ArcTone.pour, 0, 1)]);
    });

    test('sans décompte : arc plein de la couleur du résultat', () {
      for (final count in [
        null,
        const VoteTally(pour: 0, contre: 0, abstentions: 0),
      ]) {
        final plan = VoteArcPlan.of(result: VoteResult.rejete, count: count);
        expect(plan.dotted, isFalse);
        expect(plan.segments, [const ArcSegment(ArcTone.contre, 0, 1)]);
      }
    });
  });

  testWidgets('taille, libellé accessible et couleurs du thème', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const Scaffold(
          body: Center(
            child: VoteArc(
              result: VoteResult.adopte,
              count: VoteTally(pour: 503, contre: 0, abstentions: 67),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(VoteArc)), const Size(280, 154));
    expect(
      find.bySemanticsLabel('Adopté : 503 pour, 0 contre, 67 abstentions'),
      findsOneWidget,
    );
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(VoteArc),
        matching: find.byType(CustomPaint),
      ),
    );
    final painter = paint.painter! as VoteArcPainter;
    expect(painter.colorOf(ArcTone.pour), HemicycleColors.dark.pour);
    expect(
      painter.colorOf(ArcTone.abstention),
      HemicycleColors.dark.abstention,
    );
  });

  group('jauge de la liste (#75)', () {
    test('part du camp gagnant parmi les votants', () {
      // Scrutin 8706 : adopté, 503 pour sur 570 votants.
      expect(
        gaugeShare(
          result: VoteResult.adopte,
          count: const VoteTally(pour: 503, contre: 0, abstentions: 67),
        ),
        closeTo(0.88, 0.005),
      );
      // Scrutin 8610 : rejeté, 187 contre sur 338 votants.
      expect(
        gaugeShare(
          result: VoteResult.rejete,
          count: const VoteTally(pour: 151, contre: 187, abstentions: 0),
        ),
        closeTo(0.55, 0.005),
      );
    });

    test('camp gagnant minoritaire parmi les votants : jauge pleine', () {
      // Scrutin 7979 : motion de censure rejetée, seuls les pour comptés.
      expect(
        gaugeShare(
          result: VoteResult.rejete,
          count: const VoteTally(pour: 132, contre: 0, abstentions: 0),
        ),
        1,
      );
      // Scrutin 7351 : rejet préalable rejeté avec plus de pour que de contre.
      expect(
        gaugeShare(
          result: VoteResult.rejete,
          count: const VoteTally(pour: 145, contre: 82, abstentions: 0),
        ),
        1,
      );
      // Majorité spéciale : adopté sans la majorité des votants.
      expect(
        gaugeShare(
          result: VoteResult.adopte,
          count: const VoteTally(pour: 200, contre: 150, abstentions: 100),
        ),
        1,
      );
    });

    test('main levée ou sans décompte : jauge pleine', () {
      expect(
        gaugeShare(result: VoteResult.adopte, voteMode: VoteMode.mainLevee),
        1,
      );
      expect(gaugeShare(result: VoteResult.rejete), 1);
      expect(
        gaugeShare(
          result: VoteResult.rejete,
          count: const VoteTally(pour: 0, contre: 0, abstentions: 0),
        ),
        1,
      );
    });

    for (final brightness in Brightness.values) {
      testWidgets('40 × 22, libellé et couleurs (${brightness.name})', (
        tester,
      ) async {
        final colors = brightness == Brightness.dark
            ? HemicycleColors.dark
            : HemicycleColors.light;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(brightness),
            home: const Center(
              child: VoteGauge(
                result: VoteResult.rejete,
                count: VoteTally(pour: 151, contre: 187, abstentions: 0),
              ),
            ),
          ),
        );
        expect(tester.getSize(find.byType(VoteGauge)), const Size(40, 22));
        expect(
          find.bySemanticsLabel('Rejeté : 151 pour, 187 contre, 0 abstentions'),
          findsOneWidget,
        );
        final painter =
            tester
                    .widget<CustomPaint>(
                      find.descendant(
                        of: find.byType(VoteGauge),
                        matching: find.byType(CustomPaint),
                      ),
                    )
                    .painter!
                as VoteGaugePainter;
        expect(painter.share, closeTo(187 / 338, 1e-9));
        expect(painter.color, colors.contre);
        // Reste de l'arc : l'encre à 30 % sur la surface.
        expect(painter.track, Color.lerp(colors.surface, colors.ink, 0.3));
        expect(painter.track, isNot(colors.abstention));
      });
    }

    testWidgets('main levée : pleine, sans pointillés', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: VoteGauge(
              result: VoteResult.adopte,
              voteMode: VoteMode.mainLevee,
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Adopté à main levée'), findsOneWidget);
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byType(VoteGauge),
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter!
              as VoteGaugePainter;
      expect(painter.share, 1);
    });
  });
}
