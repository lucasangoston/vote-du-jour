import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:votedujour/main.dart';
import 'package:votedujour/src/decision_detail/decision_detail_repository.dart';
import 'package:votedujour/src/decision_detail/decision_route.dart';
import 'package:votedujour/src/decisions_repository.dart';
import 'package:votedujour/src/home_widget/widget_link.dart';

final _summary = DecisionSummary(
  id: 'VTANR5L17V6346',
  numero: 6346,
  type: DecisionType.ensembleTexte,
  status: DecisionStatus.confirmee,
  result: VoteResult.adopte,
  date: DateTime.utc(2026, 4, 9),
  officialTitle:
      "l'ensemble du projet de loi relatif à la restitution de biens culturels "
      "ayant fait l'objet d'une appropriation illicite (texte de la commission "
      'mixte paritaire).',
  sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/6346',
  shortTitle: 'Restitution de biens culturels',
  stage: 'Texte de compromis (CMP)',
  dossierUrl: 'https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N1',
);

// Extrait du fichier publié pour le scrutin 6346 (deux groupes sur douze).
final _detail = DecisionDetail(
  decision: _summary,
  count: const VoteCount(pour: 141, contre: 0, abstentions: 12, nonVotants: 2),
  groups: const [
    GroupVoteDetail(
      organeRef: 'PO845401',
      name: 'Rassemblement National',
      abbreviation: 'RN',
      position: GroupPosition.pour,
      count: VoteCount(pour: 30, contre: 0, abstentions: 0, nonVotants: 0),
    ),
    GroupVoteDetail(
      organeRef: 'PO845425',
      name: 'Droite Républicaine',
      abbreviation: 'DR',
      position: GroupPosition.abstention,
      count: VoteCount(pour: 5, contre: 0, abstentions: 6, nonVotants: 0),
    ),
  ],
);

/// Serveur simulé : l'index (une décision) et son fichier de détail.
MockClient _server(List<Uri> requested) => MockClient((request) async {
  requested.add(request.url);
  final body = switch (request.url.path) {
    '/v1/latest.json' => DecisionIndex(
      generatedAt: DateTime.utc(2026, 10, 17),
      decisions: [_summary],
    ).toJson(),
    '/v1/decisions/VTANR5L17V6346.json' => _detail.toJson(),
    _ => null,
  };
  return body == null
      ? http.Response('', 404)
      : http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
});

void main() {
  testWidgets('le tap sur une décision de la liste ouvre son détail', (
    tester,
  ) async {
    final requested = <Uri>[];
    final client = _server(requested);
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

    await tester.tap(find.text('Restitution de biens culturels'));
    await tester.pumpAndSettle();

    expect(
      requested.last.toString(),
      'https://example.test/v1/decisions/VTANR5L17V6346.json',
    );
    // Titre court, étape, date, résultat, type et intitulé officiel.
    expect(find.text('Décision'), findsOneWidget);
    expect(find.text('Restitution de biens culturels'), findsOneWidget);
    expect(find.text('Texte de compromis (CMP)'), findsOneWidget);
    expect(find.text('9 avril 2026'), findsOneWidget);
    expect(find.text('Adopté'), findsOneWidget);
    expect(find.text("Vote sur l'ensemble d'un texte"), findsOneWidget);
    expect(find.textContaining("L'ensemble du projet de loi"), findsOneWidget);
    // Décompte.
    expect(find.text('141'), findsOneWidget);
    expect(find.text('Abstentions '), findsOneWidget);
    expect(find.text('153 votants · 2 non-votants'), findsOneWidget);

    // Vote par groupe et lien vers le dossier, plus bas dans la page.
    await tester.scrollUntilVisible(
      find.text("Dossier sur le site de l'Assemblée"),
      200,
    );
    expect(find.textContaining('Rassemblement National'), findsOneWidget);
    expect(find.textContaining('Droite Républicaine'), findsOneWidget);
    expect(find.text('Abstention'), findsOneWidget);
    expect(find.text('5 pour · 0 contre · 6 abst.'), findsOneWidget);
    expect(find.text('Scrutin n° 6346'), findsOneWidget);
  });

  testWidgets('un lien de widget ouvre le détail sans passer par la liste', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final client = _server([]);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('Liste')),
        onGenerateRoute: (settings) => generateDecisionRoute(
          settings,
          repository: DecisionDetailRepository(
            baseUrl: 'https://example.test',
            client: client,
          ),
        ),
      ),
    );

    openWidgetLink(
      navigatorKey.currentState!,
      Uri.parse('votedujour://decisions/VTANR5L17V6346?homeWidget'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Restitution de biens culturels'), findsOneWidget);
    expect(find.text('141'), findsOneWidget);

    // Lien vers la liste : retour à l'écran d'accueil.
    openWidgetLink(
      navigatorKey.currentState!,
      Uri.parse('votedujour://decisions?homeWidget'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Liste'), findsOneWidget);
    expect(find.text('Restitution de biens culturels'), findsNothing);
  });

  test('liens profonds des widgets', () {
    expect(
      decisionIdFromDeepLink(
        Uri.parse('votedujour://decisions/VTANR5L17V6346?homeWidget'),
      ),
      'VTANR5L17V6346',
    );
    expect(
      decisionIdFromDeepLink(Uri.parse('votedujour://decisions?homeWidget')),
      isNull,
    );
    expect(decisionIdFromDeepLink(Uri.parse('https://example.test/x')), isNull);
    expect(decisionRouteName('VTANR5L17V6346'), '/decisions/VTANR5L17V6346');
  });
}
