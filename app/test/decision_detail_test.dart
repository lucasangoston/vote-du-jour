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

// Texte adopté à main levée (ticket #8) : ni numéro, ni décompte, ni groupes.
final _mainLevee = DecisionDetail(
  decision: DecisionSummary(
    id: 'L17-VD234087DEC',
    voteMode: VoteMode.mainLevee,
    type: DecisionType.ensembleTexte,
    status: DecisionStatus.confirmee,
    result: VoteResult.adopte,
    date: DateTime.utc(2026, 10, 7),
    officialTitle: "projet de loi autorisant l'approbation d'un accord",
    sourceUrl:
        'https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N54379',
    shortTitle: "Approbation d'un accord",
    stage: "1re lecture à l'AN",
    dossierUrl:
        'https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N54379',
  ),
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
    '/v1/decisions/L17-VD234087DEC.json' => _mainLevee.toJson(),
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
    // Carte du vote : résultat et décompte.
    expect(find.text('Adopté'), findsOneWidget);
    expect(find.text('141'), findsOneWidget);
    expect(find.text('abstentions'), findsOneWidget);
    expect(find.textContaining('ont voté'), findsNothing);
    // Sans arc dans l'ordre de l'hémicycle (#67) : pas de repères.
    expect(find.text('Gauche'), findsNothing);
    // Méta, titre court.
    expect(find.text('Scrutin n° 6346'), findsOneWidget);
    expect(find.text('9 avr. 2026'), findsOneWidget);
    expect(find.text('Texte de compromis (CMP)'), findsOneWidget);
    expect(find.text('Restitution de biens culturels'), findsOneWidget);

    // Qui a voté quoi, puis texte officiel et liens, plus bas.
    await tester.scrollUntilVisible(find.text('RN'), 200);
    expect(find.text('Qui a voté quoi'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Dossier législatif'), 200);
    expect(find.text('30'), findsNothing);
    // Personne contre : pas de rangée vide.
    expect(find.text('Contre'), findsNothing);
    expect(find.text('Aucun groupe'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('Droite Républicaine : Abstention')),
      findsOneWidget,
    );
    expect(find.text('Type de décision'), findsNothing);
    expect(find.text('Texte officiel'), findsOneWidget);
    expect(find.textContaining("L'ensemble du projet de loi"), findsOneWidget);
    expect(find.text('Voir le scrutin'), findsOneWidget);
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

  testWidgets('détail d\'un texte adopté à main levée', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('Liste')),
        onGenerateRoute: (settings) => generateDecisionRoute(
          settings,
          repository: DecisionDetailRepository(
            baseUrl: 'https://example.test',
            client: _server([]),
          ),
        ),
      ),
    );
    openWidgetLink(
      navigatorKey.currentState!,
      Uri.parse('votedujour://decisions/L17-VD234087DEC?homeWidget'),
    );
    await tester.pumpAndSettle();

    expect(find.text("Approbation d'un accord"), findsOneWidget);
    // Méta : date et étape, sans « Vote à main levée » (la carte le dit).
    expect(find.text('7 oct. 2026'), findsOneWidget);
    expect(find.text('1re lecture'), findsOneWidget);
    expect(find.text('Vote à main levée'), findsNothing);
    expect(find.text('À main levée · sans décompte des voix'), findsOneWidget);
    expect(find.bySemanticsLabel('Adopté à main levée'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Dossier législatif'), 200);
    expect(find.text('Qui a voté quoi'), findsNothing);
    expect(find.textContaining('ont voté'), findsNothing);
    expect(find.textContaining('Scrutin n°'), findsNothing);
    expect(find.text('Voir le scrutin'), findsNothing);
  });

  testWidgets('détail d\'une décision provisoire', (tester) async {
    final provisional = DecisionDetail(
      decision: DecisionSummary.tryFromJson({
        ..._summary.toJson(),
        'id': 'VTANR5L17V8706',
        'numero': 8706,
        'status': 'provisoire',
      })!,
      count: const VoteCount(
        pour: 503,
        contre: 0,
        abstentions: 67,
        nonVotants: 0,
      ),
    );
    final client = MockClient(
      (request) async => request.url.path == '/v1/decisions/VTANR5L17V8706.json'
          ? http.Response.bytes(
              utf8.encode(jsonEncode(provisional.toJson())),
              200,
            )
          : http.Response('', 404),
    );
    final navigatorKey = GlobalKey<NavigatorState>();
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
      Uri.parse('votedujour://decisions/VTANR5L17V8706?homeWidget'),
    );
    await tester.pumpAndSettle();

    expect(find.text('provisoire'), findsOneWidget);
    expect(find.text('503'), findsOneWidget);
    expect(
      find.text('Vote par groupe publié après confirmation.'),
      findsOneWidget,
    );
    // Le statut n'est plus répété en bas : le badge suffit.
    expect(find.text('Statut'), findsNothing);
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
    expect(
      decisionIdFromDeepLink(
        Uri.parse('votedujour://decisions/L17-VD234087DEC?homeWidget'),
      ),
      'L17-VD234087DEC',
    );
    expect(decisionIdFromDeepLink(Uri.parse('https://example.test/x')), isNull);
    expect(decisionRouteName('VTANR5L17V6346'), '/decisions/VTANR5L17V6346');
  });

  testWidgets("arc dans l'ordre de l'hémicycle : repères Gauche et Droite, "
      'libellé accessible inchangé (#67)', (tester) async {
    final hemicycle = _detail.withDecision(
      _summary.withArc(const [
        HemicycleSegment(ArcPosition.abstention, 12),
        HemicycleSegment(ArcPosition.pour, 141),
      ]),
    );
    final client = MockClient(
      (request) async =>
          http.Response.bytes(utf8.encode(jsonEncode(hemicycle.toJson())), 200),
    );
    final navigatorKey = GlobalKey<NavigatorState>();
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

    expect(find.text('Gauche'), findsOneWidget);
    expect(find.text('Droite'), findsOneWidget);
    expect(
      tester.getCenter(find.text('Gauche')).dx,
      lessThan(tester.getCenter(find.text('Droite')).dx),
    );
    expect(
      find.bySemanticsLabel('Adopté : 141 pour, 0 contre, 12 abstentions'),
      findsOneWidget,
    );
  });
}
