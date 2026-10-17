import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:votedujour/main.dart';
import 'package:votedujour/src/decisions_repository.dart';
import 'package:votedujour/src/home_widget/widget_snapshot.dart';
import 'package:votedujour/src/provisional_badge.dart';

/// Décision détectée pendant la séance (ticket #10), telle que la publie le
/// job ; le second scrutin est confirmé, sans champ `status` (optionnel).
final _index = {
  'schemaVersion': 1,
  'generatedAt': '2026-10-20T15:00:00.000Z',
  'decisions': [
    {
      'id': 'VTANR5L17V8706',
      'numero': 8706,
      'voteMode': 'scrutin_public',
      'type': 'ensemble',
      'status': 'provisoire',
      'result': 'adopte',
      'date': '2026-10-13',
      'officialTitle':
          "la proposition de loi organique visant à adapter l'autorité "
          'judiciaire à la lutte contre les violences sexuelles et '
          'intrafamiliales (première lecture).',
      'sourceUrl': 'https://www.assemblee-nationale.fr/dyn/17/scrutins/8706',
      'shortTitle':
          "Proposition de loi organique visant à adapter l'autorité "
          'judiciaire à la lutte contre les violences sexuelles et '
          'intrafamiliales',
      'stage': "1re lecture à l'AN",
    },
    {
      'id': 'VTANR5L17V1194',
      'numero': 1194,
      'type': 'ensemble',
      'result': 'adopte',
      'date': '2025-04-01',
      'officialTitle':
          "l'ensemble de la proposition de loi visant à sortir la France du "
          'piège du narcotrafic (première lecture).',
      'sourceUrl': 'https://www.assemblee-nationale.fr/dyn/17/scrutins/1194',
      'shortTitle': 'Sortir la France du piège du narcotrafic',
      'stage': "1re lecture à l'AN",
    },
  ],
};

void main() {
  testWidgets('badge « provisoire » sur la seule décision non confirmée', (
    tester,
  ) async {
    final client = MockClient(
      (_) async => http.Response.bytes(utf8.encode(jsonEncode(_index)), 200),
    );
    await tester.pumpWidget(
      VoteDuJourApp(
        repository: DecisionsRepository(
          baseUrl: 'https://example.test',
          client: client,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ProvisionalBadge), findsOneWidget);
    expect(find.text('provisoire'), findsOneWidget);
    expect(find.text('Adopté'), findsNWidgets(2));
    expect(
      find.text('Sortir la France du piège du narcotrafic'),
      findsOneWidget,
    );
    // Le badge est sur la ligne de la décision provisoire (la première).
    expect(
      tester.getTopLeft(find.byType(ProvisionalBadge)).dy,
      lessThan(
        tester
            .getTopLeft(find.text('Sortir la France du piège du narcotrafic'))
            .dy,
      ),
    );
  });

  test(
    'widget : « provisoire » s\'ajoute à l\'étape, le reste ne change pas',
    () {
      final index = DecisionIndex.fromJson(_index);
      final snapshot = WidgetSnapshot.fromIndex(
        index,
        savedAt: DateTime.utc(2026, 10, 20, 15),
      );
      expect(snapshot.decisions.map((d) => d.stage), [
        "1re lecture à l'AN · provisoire",
        "1re lecture à l'AN",
      ]);
      expect(
        snapshot.decisions.first.title,
        WidgetDecision.fromSummary(
          DecisionSummary.tryFromJson({
            ...(_index['decisions'] as List).first as Map<String, Object?>,
            'status': 'confirmee',
          })!,
        ).title,
      );

      // Sans étape : la mention seule, avec une majuscule.
      final noStage = DecisionSummary.tryFromJson(
        {...(_index['decisions'] as List).first as Map<String, Object?>}
          ..remove('stage'),
      )!;
      expect(WidgetDecision.fromSummary(noStage).stage, 'Provisoire');
    },
  );
}
