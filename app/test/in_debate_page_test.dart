import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:votedujour/src/decision_list_page.dart';
import 'package:votedujour/src/decisions_repository.dart';
import 'package:votedujour/src/hemicycle/hemicycle_places.dart';
import 'package:votedujour/src/hemicycle/hemicycle_seats.dart';
import 'package:votedujour/src/in_debate/in_debate_page.dart';
import 'package:votedujour/src/in_debate/in_debate_route.dart';
import 'package:votedujour/src/notifications/important_votes_notifications.dart';
import 'package:votedujour/src/theme.dart';

const _ref = 'DLR5L17N52100';

/// Le texte en débat des maquettes (`design/maquettes/build.mjs`) : projet
/// de loi de financement de la sécurité sociale pour 2027, 4 articles
/// adoptés, 12 supprimés, 2 rejetés.
InDebate _plfss({bool withSummary = true, bool withArticles = true}) {
  var numero = 9000;
  DebatedArticle article(ArticleOutcome outcome) => DebatedArticle(
    number: '${numero - 8999}',
    outcome: outcome,
    date: DateTime.utc(2026, 10, 23),
    scrutinRef: 'VTANR5L17V${numero++}',
  );
  return InDebate(
    dossierRef: _ref,
    shortTitle: 'Projet de loi de financement de la sécurité sociale pour 2027',
    dossierUrl: 'https://www.assemblee-nationale.fr/dyn/17/dossiers/$_ref',
    seanceRef: 'RUANR5L17S2027IDS31000',
    startsAt: DateTime.utc(2026, 10, 23, 7),
    articles: withArticles
        ? [
            for (var i = 0; i < 4; i++) article(ArticleOutcome.adopte),
            for (var i = 0; i < 12; i++) article(ArticleOutcome.supprime),
            for (var i = 0; i < 2; i++) article(ArticleOutcome.rejete),
          ]
        : const [],
    summary: withSummary
        ? const PlainSummary(
            title: 'Le budget de la Sécurité sociale pour 2027',
            shortTitle: 'Sécurité sociale 2027',
            explanation:
                'Le texte fixe le budget de la Sécurité sociale pour 2027 : '
                'ce qu’elle prévoit de recevoir et de dépenser pour la santé, '
                'les retraites, la famille et l’autonomie.',
            points: [
              'Il prévoit les recettes de la Sécurité sociale, cotisations et '
                  'impôts affectés.',
              'Il fixe l’objectif de dépenses de l’assurance maladie pour '
                  'l’année.',
              'Il contient des mesures sur les retraites, les prestations '
                  'familiales et la perte d’autonomie.',
            ],
            promptVersion: 1,
          )
        : null,
  );
}

/// Vendredi 23 octobre 2026, 11h à Paris.
final _now = DateTime.utc(2026, 10, 23, 9);

UpcomingItem _finalVote(DateTime startsAt, {String? dossierRef = _ref}) =>
    UpcomingItem(
      id: 'PT1',
      kind: UpcomingKind.voteSolennel,
      startsAt: startsAt,
      seanceRef: 'S2',
      label: 'Vote solennel sur le projet de loi de financement',
      shortTitle: 'Sécurité sociale 2027',
      dossierRef: dossierRef,
    );

/// Dépôt servant l'index [index] (ou une erreur 503 sans index).
DecisionsRepository _repository(DecisionIndex? index) => DecisionsRepository(
  baseUrl: 'https://example.test',
  client: MockClient(
    (request) async => index == null
        ? http.Response('', 503)
        : http.Response.bytes(utf8.encode(jsonEncode(index.toJson())), 200),
  ),
);

DecisionIndex _index(InDebate? inDebate, {List<UpcomingItem>? upcoming}) =>
    DecisionIndex(
      generatedAt: _now,
      decisions: const [],
      upcoming: upcoming,
      inDebate: inDebate,
    );

Future<void> _pump(
  WidgetTester tester,
  DecisionIndex? index, {
  Brightness brightness = Brightness.light,
  String dossierRef = _ref,
  Size size = const Size(390, 844),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(brightness),
      home: InDebatePage(
        dossierRef: dossierRef,
        repository: _repository(index),
        now: _now,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('liens', () {
    test('lien profond de l’écran « En débat »', () {
      expect(
        inDebateRefFromDeepLink(Uri.parse('votedujour://en-debat/$_ref')),
        _ref,
      );
      expect(
        inDebateRefFromDeepLink(Uri.parse('votedujour://en-debat')),
        isNull,
      );
      expect(
        inDebateRefFromDeepLink(Uri.parse('votedujour://decisions/$_ref')),
        isNull,
      );
      expect(inDebateRouteName(_ref), '/en-debat/$_ref');
    });

    test('notification : dossierRef, sinon le lien (celui du job)', () {
      expect(
        inDebateRefFromNotification({
          'dossierRef': _ref,
          'link': 'votedujour://en-debat/$_ref',
        }),
        _ref,
      );
      expect(
        inDebateRefFromNotification({'link': 'votedujour://en-debat/$_ref'}),
        _ref,
      );
      expect(inDebateRefFromNotification({'dossierRef': 'a/b'}), isNull);
      expect(
        inDebateRefFromNotification({'decisionId': 'VTANR5L17V1'}),
        isNull,
      );
      expect(decisionIdFromNotification({'dossierRef': _ref}), isNull);
    });
  });

  group('finalVoteLabel', () {
    test('à venir, sauf vote solennel du même dossier à l’ordre du jour', () {
      final d = _plfss();
      expect(finalVoteLabel(d, null, now: _now), 'Vote final à venir');
      expect(
        finalVoteLabel(d, [
          _finalVote(DateTime.utc(2026, 10, 27, 14), dossierRef: 'DLR2'),
        ], now: _now),
        'Vote final à venir',
      );
      expect(
        finalVoteLabel(d, [
          _finalVote(DateTime.utc(2026, 10, 27, 14)),
        ], now: _now),
        'Vote final le mardi 27 octobre',
      );
      expect(
        finalVoteLabel(d, [
          _finalVote(DateTime.utc(2026, 10, 24, 14)),
        ], now: _now),
        'Vote final demain',
      );
      expect(
        finalVoteLabel(d, [
          _finalVote(DateTime.utc(2026, 10, 23, 14)),
        ], now: _now),
        "Vote final aujourd'hui",
      );
    });
  });

  test('hémicycle d’attente : toutes les places, même taille, même gris', () {
    const grey = Color(0xFF888888);
    final marks = waitingSeatMarks(grey);
    expect(marks, hasLength(hemicyclePlaces.length));
    expect(marks.map((m) => m.shape).toSet(), {SeatShape.disc});
    expect(marks.map((m) => m.color).toSet(), {grey});
    expect(marks.map((m) => m.opacity).toSet(), {1});
    expect(marks.every((m) => m.outline == null), isTrue);
  });

  for (final (brightness, theme) in [
    (Brightness.light, 'jour'),
    (Brightness.dark, 'nuit'),
  ]) {
    group('écran ($theme)', () {
      testWidgets('maquette « debat »', (tester) async {
        await _pump(
          tester,
          _index(_plfss()),
          brightness: brightness,
          size: const Size(390, 1560),
        );
        expect(find.byType(WaitingHemicycle), findsOneWidget);
        expect(find.byType(HemicycleSeats), findsNothing);
        expect(find.text('En débat'), findsOneWidget);
        expect(find.text('Vote final à venir'), findsOneWidget);
        // « En débat » sous l'hémicycle.
        expect(
          tester.getTopLeft(find.text('En débat')).dy,
          greaterThan(tester.getBottomLeft(find.byType(WaitingHemicycle)).dy),
        );
        expect(
          find.text(
            'Projet de loi de financement de la sécurité sociale pour 2027',
          ),
          findsOneWidget,
        );
        expect(find.text('Sécurité sociale 2027'), findsOneWidget);
        expect(find.textContaining('Le texte fixe le budget'), findsOneWidget);
        expect(find.text('Ce que prévoit le texte'), findsOneWidget);
        expect(
          find.textContaining('Il fixe l’objectif de dépenses'),
          findsOneWidget,
        );
        expect(find.text('Articles votés'), findsOneWidget);
        expect(
          find.bySemanticsLabel('4 articles adoptés, 12 supprimés, 2 rejetés'),
          findsOneWidget,
        );
        expect(find.text('Dossier législatif'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await expectLater(
          find.byType(InDebatePage),
          matchesGoldenFile('goldens/en-debat-$theme.png'),
        );
      });
    });
  }

  testWidgets('vote final inscrit à l’ordre du jour', (tester) async {
    await _pump(
      tester,
      _index(_plfss(), upcoming: [_finalVote(DateTime.utc(2026, 10, 27, 14))]),
    );
    expect(find.text('Vote final le mardi 27 octobre'), findsOneWidget);
  });

  testWidgets('sans résumé ni article voté', (tester) async {
    await _pump(
      tester,
      _index(_plfss(withSummary: false, withArticles: false)),
      size: const Size(390, 1200),
    );
    expect(
      find.text(
        'Projet de loi de financement de la sécurité sociale pour 2027',
      ),
      findsOneWidget,
      reason: 'titre, sans intitulé répété au-dessus',
    );
    expect(find.text('Ce que prévoit le texte'), findsNothing);
    expect(find.text('Articles votés'), findsOneWidget);
    expect(find.text(noArticleNotice), findsOneWidget);
    expect(find.byType(ArticleTally), findsNothing);
  });

  testWidgets('un article adopté : au singulier', (tester) async {
    final d = _plfss();
    await _pump(
      tester,
      _index(
        InDebate(
          dossierRef: d.dossierRef,
          shortTitle: d.shortTitle,
          dossierUrl: d.dossierUrl,
          seanceRef: d.seanceRef,
          startsAt: d.startsAt,
          articles: [d.articles.first],
        ),
      ),
      size: const Size(390, 1200),
    );
    expect(
      find.bySemanticsLabel('1 article adopté, 0 supprimé, 0 rejeté'),
      findsOneWidget,
    );
  });

  testWidgets('autre texte en débat : l’écran le dit', (tester) async {
    await _pump(tester, _index(_plfss()), dossierRef: 'DLR5L17N1');
    expect(find.text('Ce texte n’est plus en débat.'), findsOneWidget);
    expect(find.text('Dossier législatif'), findsOneWidget);
    expect(find.byType(WaitingHemicycle), findsNothing);
  });

  testWidgets('index indisponible : réessayer', (tester) async {
    await _pump(tester, null);
    expect(find.text('Texte indisponible.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  group('accueil : plus de section « En débat » (#77, #79)', () {
    Future<void> pumpList(WidgetTester tester, Map<String, Object?> json) {
      final body = utf8.encode(jsonEncode(json));
      final client = MockClient((_) async => http.Response.bytes(body, 200));
      return tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: DecisionListPage(
            repository: DecisionsRepository(
              baseUrl: 'https://example.test',
              client: client,
            ),
          ),
        ),
      );
    }

    final decision = {
      'id': 'VTANR5L17V8706',
      'numero': 8706,
      'type': 'ensemble',
      'status': 'confirmee',
      'result': 'adopte',
      'date': '2026-10-20',
      'officialTitle': "l'ensemble du projet de loi exemple.",
      'sourceUrl': 'https://www.assemblee-nationale.fr/dyn/17/scrutins/8706',
    };

    testWidgets('plus dans la liste : « À venir » et les décisions seulement '
        '(#77, #79)', (tester) async {
      final now = DateTime.now().toUtc();
      final plfss = _plfss();
      final inDebate = InDebate(
        dossierRef: plfss.dossierRef,
        shortTitle: plfss.shortTitle,
        dossierUrl: plfss.dossierUrl,
        seanceRef: plfss.seanceRef,
        startsAt: now.subtract(const Duration(hours: 2)),
        articles: plfss.articles.take(2).toList(),
      );
      await pumpList(tester, {
        'schemaVersion': 1,
        'generatedAt': '2026-10-21T10:00:00.000Z',
        'decisions': [decision],
        'upcoming': [
          UpcomingItem(
            id: 'PT1',
            kind: UpcomingKind.voteSolennel,
            startsAt: now.add(const Duration(days: 2)),
            seanceRef: 'S1',
            label: 'Vote solennel',
            shortTitle: 'Texte voté bientôt',
          ).toJson(),
        ],
        'inDebate': inDebate.toJson(),
      });
      await tester.pumpAndSettle();

      expect(find.text('À venir'), findsOneWidget);
      expect(find.text("L'ensemble du projet de loi exemple."), findsOneWidget);
      expect(find.text('En débat'), findsNothing);
    });

    testWidgets('ancien index sans `inDebate` : rien', (tester) async {
      await pumpList(tester, {
        'schemaVersion': 1,
        'generatedAt': '2026-10-21T10:00:00.000Z',
        'decisions': [decision],
      });
      await tester.pumpAndSettle();

      expect(find.text("L'ensemble du projet de loi exemple."), findsOneWidget);
      expect(find.text('En débat'), findsNothing);
    });
  });
}
