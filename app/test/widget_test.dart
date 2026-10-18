import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:votedujour/main.dart';
import 'package:votedujour/src/decisions_repository.dart';
import 'package:votedujour/src/relative_date.dart';

void main() {
  testWidgets('affiche les décisions publiées et la source', (tester) async {
    // Dates relatives : un vote du jour et un vote plus ancien.
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final older = DateTime.utc(now.year, now.month, now.day - 30);
    final requested = <Uri>[];
    final client = MockClient((request) async {
      requested.add(request.url);
      final index = DecisionIndex(
        generatedAt: DateTime.utc(2026, 10, 17, 10),
        decisions: [
          DecisionSummary(
            id: 'VTANR5L17V8706',
            numero: 8706,
            type: DecisionType.ensembleTexte,
            status: DecisionStatus.confirmee,
            result: VoteResult.adopte,
            date: today,
            officialTitle: "l'ensemble du projet de loi exemple.",
            sourceUrl:
                'https://www.assemblee-nationale.fr/dyn/17/scrutins/8706',
          ),
          DecisionSummary(
            id: 'VTANR5L17V8707',
            numero: 8707,
            type: DecisionType.rejetPrealable,
            status: DecisionStatus.confirmee,
            result: VoteResult.rejete,
            date: older,
            officialTitle: 'la motion de rejet préalable exemple.',
            sourceUrl:
                'https://www.assemblee-nationale.fr/dyn/17/scrutins/8707',
          ),
        ],
      );
      return http.Response.bytes(utf8.encode(jsonEncode(index.toJson())), 200);
    });

    await tester.pumpWidget(
      VoteDuJourApp(
        repository: DecisionsRepository(
          baseUrl: 'https://example.test',
          client: client,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requested.single.toString(), 'https://example.test/v1/latest.json');
    expect(find.text("L'ensemble du projet de loi exemple."), findsOneWidget);
    expect(find.text('Adopté'), findsOneWidget);
    expect(find.text('Rejeté'), findsOneWidget);
    // Décisions groupées par jour (#29).
    expect(find.text('Décisions'), findsOneWidget);
    expect(find.text("Aujourd'hui"), findsOneWidget);
    expect(find.text(dayGroupLabel(older, now: now)), findsOneWidget);
    expect(find.textContaining('Licence Ouverte'), findsOneWidget);
  });
}
