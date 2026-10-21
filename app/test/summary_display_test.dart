import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:votedujour/main.dart';
import 'package:votedujour/src/decision_detail/decision_detail_page.dart';
import 'package:votedujour/src/decision_detail/decision_detail_repository.dart';
import 'package:votedujour/src/decisions_repository.dart';
import 'package:votedujour/src/home_widget/widget_snapshot.dart';

const _summary = PlainSummary(
  title: "Retour de l'âge légal de départ à 62 ans",
  explanation:
      "Le texte prévoit d'annuler le relèvement de l'âge légal de départ à "
      'la retraite.',
  points: [
    "L'âge légal de départ revient à 62 ans.",
    'La durée de cotisation revient à 42 annuités.',
    'Les pertes de recettes sont compensées par une taxe sur le tabac.',
  ],
  promptVersion: 1,
);

final _decision = DecisionSummary(
  id: 'VTANR5L17V217',
  numero: 217,
  type: DecisionType.ensembleTexte,
  status: DecisionStatus.confirmee,
  result: VoteResult.rejete,
  date: DateTime.utc(2024, 10, 31),
  officialTitle:
      "l'ensemble de la proposition de loi visant à restaurer un système de "
      'retraite plus juste (première lecture).',
  sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/217',
  shortTitle: 'Restaurer un système de retraite plus juste',
  stage: "1re lecture à l'AN",
).withSummary(_summary);

/// Serveur simulé : l'index (sans les points) et le fichier de détail
/// (avec les points), comme les publie le job.
MockClient _server() => MockClient((request) async {
  final body = switch (request.url.path) {
    '/v1/latest.json' => DecisionIndex(
      generatedAt: DateTime.utc(2026, 10, 18),
      decisions: [_decision],
    ).toJson(),
    '/v1/decisions/VTANR5L17V217.json' => DecisionDetail(
      decision: _decision,
      count: const VoteCount(
        pour: 100,
        contre: 300,
        abstentions: 0,
        nonVotants: 1,
      ),
    ).toJson(),
    _ => null,
  };
  return body == null
      ? http.Response('', 404)
      : http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
});

void main() {
  testWidgets('la liste affiche la phrase sous le titre, le détail les '
      'points', (tester) async {
    final client = _server();
    await tester.pumpWidget(
      VoteDuJourApp(
        repository: DecisionsRepository(
          baseUrl: 'https://example.test',
          client: client,
        ),
        detailRepository: DecisionDetailRepository(
          baseUrl: 'https://example.test',
          client: client,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text("Retour de l'âge légal de départ à 62 ans"),
      findsOneWidget,
    );
    expect(find.text(_summary.explanation), findsOneWidget);
    // Les points ne sont que dans le détail.
    expect(find.text(summaryPointsHeading), findsNothing);

    await tester.tap(find.text("Retour de l'âge légal de départ à 62 ans"));
    await tester.pumpAndSettle();

    expect(find.text(_summary.explanation), findsOneWidget);
    await tester.scrollUntilVisible(find.text(_summary.points.last), 200);
    expect(find.text(summaryPointsHeading), findsOneWidget);
    // Mention discrète sous l'intertitre : les points viennent d'une IA.
    expect(find.text(aiSummaryNotice), findsOneWidget);
    expect(aiSummaryNotice, 'Résumé par IA');
    for (final point in _summary.points) {
      expect(find.text(point), findsOneWidget);
    }
    // L'intitulé officiel reste affiché.
    await tester.scrollUntilVisible(
      find.textContaining("L'ensemble de la proposition de loi"),
      200,
    );
    expect(
      find.textContaining("L'ensemble de la proposition de loi"),
      findsOneWidget,
    );
  });

  testWidgets('sans résumé : ni phrase ni intertitre', (tester) async {
    final plain = _decision.withSummary(null);
    final client = MockClient((request) async {
      final body = request.url.path == '/v1/latest.json'
          ? DecisionIndex(
              generatedAt: DateTime.utc(2026, 10, 18),
              decisions: [plain],
            ).toJson()
          : DecisionDetail(decision: plain).toJson();
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
    });
    await tester.pumpWidget(
      VoteDuJourApp(
        repository: DecisionsRepository(
          baseUrl: 'https://example.test',
          client: client,
        ),
        detailRepository: DecisionDetailRepository(
          baseUrl: 'https://example.test',
          client: client,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restaurer un système de retraite plus juste'));
    await tester.pumpAndSettle();
    expect(find.text(summaryPointsHeading), findsNothing);
    expect(find.text(aiSummaryNotice), findsNothing);
    expect(find.byType(Scaffold), findsOneWidget);
  });

  test('l\'instantané des widgets porte le titre et la phrase du résumé', () {
    final snapshot = WidgetSnapshot.fromIndex(
      DecisionIndex(
        generatedAt: DateTime.utc(2026, 10, 18),
        decisions: [_decision, _decision.withSummary(null)],
      ),
      savedAt: DateTime.utc(2026, 10, 18, 9),
    );
    expect(snapshot.toJson()['decisions'], [
      {
        'id': 'VTANR5L17V217',
        'result': 'rejete',
        'date': '2024-10-31',
        'title': "Retour de l'âge légal de départ à 62 ans",
        'stage': "1re lecture à l'AN",
        'explanation': _summary.explanation,
        'voteMode': 'scrutin_public',
      },
      {
        'id': 'VTANR5L17V217',
        'result': 'rejete',
        'date': '2024-10-31',
        'title': 'Restaurer un système de retraite plus juste',
        'stage': "1re lecture à l'AN",
        'voteMode': 'scrutin_public',
      },
    ]);
  });
}
