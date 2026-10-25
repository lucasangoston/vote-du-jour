import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:votedujour/src/decision_list_page.dart';
import 'package:votedujour/src/decisions_repository.dart';
import 'package:votedujour/src/hemicycle/vote_arc.dart';
import 'package:votedujour/src/theme.dart';

// Scrutins de la maquette `liste` (#75).
final _decisions = [
  DecisionSummary(
    id: 'VTANR5L17V8706',
    numero: 8706,
    type: DecisionType.ensembleTexte,
    status: DecisionStatus.confirmee,
    result: VoteResult.adopte,
    date: DateTime.utc(2026, 10, 13),
    officialTitle:
        "la proposition de loi organique visant à adapter l'autorité "
        'judiciaire à la lutte contre les violences sexuelles et '
        'intrafamiliales (première lecture).',
    shortTitle: 'Juges des violences sexuelles',
    sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/8706',
    count: const VoteTally(pour: 503, contre: 0, abstentions: 67),
  ),
  DecisionSummary(
    id: 'VTANR5L17V8610',
    numero: 8610,
    type: DecisionType.resolution,
    status: DecisionStatus.confirmee,
    result: VoteResult.rejete,
    date: DateTime.utc(2026, 10, 8),
    officialTitle:
        'la proposition de résolution visant à mobiliser la commande '
        "publique au service de l'emploi (article 34-1 de la Constitution).",
    shortTitle: 'Commande publique et emploi',
    sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/8610',
    count: const VoteTally(pour: 151, contre: 187, abstentions: 0),
  ),
  DecisionSummary(
    id: 'VTANR5L17V8600',
    numero: 8600,
    type: DecisionType.rejetPrealable,
    status: DecisionStatus.confirmee,
    result: VoteResult.rejete,
    date: DateTime.utc(2026, 10, 8),
    officialTitle: 'la motion de rejet préalable exemple.',
    sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/8600',
    count: const VoteTally(pour: 0, contre: 300, abstentions: 0),
  ),
];

Future<void> _pumpList(WidgetTester tester, Brightness brightness) async {
  final client = MockClient((request) async {
    final index = DecisionIndex(
      generatedAt: DateTime.utc(2026, 10, 17, 10),
      decisions: _decisions,
    );
    return http.Response.bytes(utf8.encode(jsonEncode(index.toJson())), 200);
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness),
      home: DecisionListPage(
        repository: DecisionsRepository(
          baseUrl: 'https://example.test',
          client: client,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

VoteGaugePainter _gaugeOf(WidgetTester tester, String title) {
  final row = find.ancestor(
    of: find.text(title),
    matching: find.byType(DecisionRow),
  );
  final paint = tester.widget<CustomPaint>(
    find.descendant(of: row, matching: find.byType(CustomPaint)),
  );
  return paint.painter! as VoteGaugePainter;
}

void main() {
  for (final brightness in Brightness.values) {
    final colors = brightness == Brightness.dark
        ? HemicycleColors.dark
        : HemicycleColors.light;

    testWidgets('jauge d\'une couleur et résultat seul (${brightness.name})', (
      tester,
    ) async {
      await _pumpList(tester, brightness);

      expect(find.text('Décisions'), findsOneWidget);
      // 8706 : jauge verte à 88 %.
      final adopted = _gaugeOf(tester, 'Juges des violences sexuelles');
      expect(adopted.share, closeTo(0.88, 0.005));
      expect(adopted.color, colors.pour);
      // 8610 : rouge à 55 %.
      final rejected = _gaugeOf(tester, 'Commande publique et emploi');
      expect(rejected.share, closeTo(0.55, 0.005));
      expect(rejected.color, colors.contre);
      // 100 % : arc plein.
      expect(
        _gaugeOf(tester, 'La motion de rejet préalable exemple.').share,
        1,
      );
      expect(adopted.track, Color.lerp(colors.surface, colors.ink, 0.3));

      // « Adopté » ou « Rejeté » seul : ni chiffres ni type dans la ligne.
      expect(find.text('Adopté'), findsOneWidget);
      expect(find.text('Rejeté'), findsNWidgets(2));
      expect(find.text('Résolution'), findsNothing);
      expect(find.text('Rejet préalable'), findsNothing);
      expect(find.textContaining('503'), findsNothing);
      expect(find.textContaining('187'), findsNothing);
      // Les chiffres restent dans le libellé accessible de la jauge.
      expect(
        find.bySemanticsLabel('Adopté : 503 pour, 0 contre, 67 abstentions'),
        findsOneWidget,
      );
    });

    testWidgets('filtres Tout / Textes / Résolutions / Motions '
        '(${brightness.name})', (tester) async {
      await _pumpList(tester, brightness);
      for (final label in ['Tout', 'Textes', 'Résolutions', 'Motions']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byType(DecisionRow), findsNWidgets(3));

      await tester.tap(find.text('Résolutions'));
      await tester.pumpAndSettle();
      expect(find.byType(DecisionRow), findsOneWidget);
      expect(find.text('Commande publique et emploi'), findsOneWidget);

      await tester.tap(find.text('Textes'));
      await tester.pumpAndSettle();
      expect(find.byType(DecisionRow), findsOneWidget);
      expect(find.text('Juges des violences sexuelles'), findsOneWidget);

      await tester.tap(find.text('Motions'));
      await tester.pumpAndSettle();
      expect(
        find.text('La motion de rejet préalable exemple.'),
        findsOneWidget,
      );
      expect(find.byType(DecisionRow), findsOneWidget);

      await tester.tap(find.text('Tout'));
      await tester.pumpAndSettle();
      expect(find.byType(DecisionRow), findsNWidgets(3));
    });
  }
}
