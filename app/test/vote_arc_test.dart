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

  testWidgets('mini-arc de la liste : 40 × 22', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: VoteArc.mini(
            result: VoteResult.rejete,
            voteMode: VoteMode.mainLevee,
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(VoteArc)), const Size(40, 22));
    expect(find.bySemanticsLabel('Rejeté à main levée'), findsOneWidget);
  });
}
