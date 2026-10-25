import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:votedujour/src/decision_detail/decision_detail_page.dart';
import 'package:votedujour/src/decision_detail/decision_detail_repository.dart';
import 'package:votedujour/src/decision_detail/decision_route.dart';
import 'package:votedujour/src/decision_list_page.dart';
import 'package:votedujour/src/decisions_repository.dart';
import 'package:votedujour/src/hemicycle/hemicycle_seats.dart';
import 'package:votedujour/src/hemicycle/vote_arc.dart';
import 'package:votedujour/src/home_page.dart';
import 'package:votedujour/src/theme.dart';

/// Vendredi 23 octobre 2026, jour des maquettes.
final _now = DateTime(2026, 10, 23, 10);

/// Fichiers de détail des scrutins 8706 (adopté) et 8610 (rejeté), avec
/// leurs sièges, et le titre court des maquettes.
DecisionDetail _fixture(int numero, String shortTitle) {
  final detail = DecisionDetail.fromJson(
    jsonDecode(File('test/fixtures/detail_$numero.json').readAsStringSync()),
  );
  final summary = detail.decision.summary!;
  return detail.withDecision(
    detail.decision.withSummary(
      PlainSummary(
        title: summary.title,
        explanation: summary.explanation,
        promptVersion: summary.promptVersion,
        points: summary.points,
        shortTitle: shortTitle,
      ),
    ),
  );
}

final _d8706 = _fixture(8706, 'Juges des violences sexuelles');
final _d8610 = _fixture(8610, 'Achats publics : priorité nationale');

/// Vote solennel du mardi 3 novembre, séance de 15 h (heure de Paris).
final _plf = UpcomingItem(
  id: 'PT53449',
  kind: UpcomingKind.voteSolennel,
  startsAt: DateTime.utc(2026, 11, 3, 14),
  seanceRef: 'S30977',
  label: 'Vote solennel sur le projet de loi de finances pour 2027',
  shortTitle: "Budget de l'État 2027",
  dossierUrl: 'https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N1',
);

/// Décision plus ancienne du même texte que 8706 : pas de seconde carte.
final _older8706 = DecisionSummary(
  id: 'VTANR5L17V8600',
  numero: 8600,
  type: DecisionType.rejetPrealable,
  status: DecisionStatus.confirmee,
  result: VoteResult.adopte,
  date: DateTime.utc(2026, 10, 7),
  officialTitle: 'la motion de rejet préalable.',
  sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/8600',
  shortTitle: 'Motion sur le même texte',
  dossierUrl: _d8706.decision.dossierUrl,
);

/// Texte en débat : annoncé par une notification, jamais en carte.
final _inDebate = InDebate(
  dossierRef: 'DLR5L17N2',
  shortTitle: 'Texte en débat',
  dossierUrl: 'https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N2',
  seanceRef: 'S30970',
  startsAt: DateTime.utc(2026, 10, 23, 7),
  articles: const [],
);

final _index = DecisionIndex(
  generatedAt: DateTime.utc(2026, 10, 23, 8),
  decisions: [_d8706.decision, _older8706, _d8610.decision],
  upcoming: [_plf],
  inDebate: _inDebate,
);

/// Ouvre l'accueil sur un écran de 390 × 844, avec l'index [index] et les
/// fichiers de détail de 8706 et 8610 (aucun avec [withDetails] faux).
Future<List<Uri>> _pumpHome(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  DecisionIndex? index,
  bool withDetails = true,
}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final requested = <Uri>[];
  final client = MockClient((request) async {
    requested.add(request.url);
    final body = switch (request.url.path) {
      '/v1/latest.json' => (index ?? _index).toJson(),
      '/v1/decisions/VTANR5L17V8706.json' when withDetails => _d8706.toJson(),
      '/v1/decisions/VTANR5L17V8610.json' when withDetails => _d8610.toJson(),
      _ => null,
    };
    return body == null
        ? http.Response('', 404)
        : http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
  });
  final detailRepository = DecisionDetailRepository(
    baseUrl: 'https://example.test',
    client: client,
  );
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(brightness),
      home: HomePage(
        repository: DecisionsRepository(
          baseUrl: 'https://example.test',
          client: client,
        ),
        detailRepository: detailRepository,
        now: _now,
      ),
      onGenerateRoute: (settings) =>
          generateDecisionRoute(settings, repository: detailRepository),
    ),
  );
  await tester.pumpAndSettle();
  return requested;
}

/// Fait passer la pile à la carte suivante.
Future<void> _swipe(WidgetTester tester) async {
  await tester.fling(
    find.text("Budget de l'État 2027"),
    const Offset(-200, 0),
    1000,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('un seul appui ouvre le détail, même juste après un glissement', (
    tester,
  ) async {
    await _pumpHome(tester);
    await tester.fling(
      find.text("Budget de l'État 2027"),
      const Offset(-200, 0),
      1000,
    );
    // La carte se recale : un appui 0,3 s après le geste doit déjà compter
    // (le défilement en cours ignore les touchers).
    for (var t = 0; t < 300; t += 16) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.tap(find.text('Juges des violences sexuelles'));
    await tester.pumpAndSettle();
    expect(find.byType(DecisionDetailPage), findsOneWidget);
  });

  group('cartes de l\'accueil', () {
    test('le vote solennel, puis une carte par texte, sans « En débat »', () {
      final cards = homeCards(_index, now: _now);
      expect(cards, hasLength(3));
      expect((cards[0] as UpcomingVoteCard).item.id, _plf.id);
      expect(
        [for (final c in cards.skip(1)) (c as DecisionCard).decision.id],
        ['VTANR5L17V8706', 'VTANR5L17V8610'],
      );
    });

    test('vote passé : pas de carte ; au plus $homeDecisionCount '
        'décisions', () {
      final decisions = [
        for (var i = 0; i < 5; i++)
          DecisionSummary(
            id: 'VTANR5L17V${9000 + i}',
            numero: 9000 + i,
            type: DecisionType.ensembleTexte,
            status: DecisionStatus.confirmee,
            result: VoteResult.adopte,
            date: DateTime.utc(2026, 10, 20 - i),
            officialTitle: 'texte $i',
            sourceUrl: 'https://example.test/$i',
          ),
      ];
      final cards = homeCards(
        DecisionIndex(
          generatedAt: _now,
          decisions: decisions,
          upcoming: [_plf],
        ),
        now: DateTime(2026, 11, 4),
      );
      expect(cards, hasLength(homeDecisionCount));
      expect(cards, everyElement(isA<DecisionCard>()));
    });
  });

  for (final brightness in Brightness.values) {
    final theme = brightness == Brightness.light ? 'jour' : 'nuit';

    group('accueil ($theme)', () {
      testWidgets('date du jour, carte vote solennel, la suivante dépasse', (
        tester,
      ) async {
        final requested = await _pumpHome(tester, brightness: brightness);

        expect(find.text('Vendredi 23 octobre'), findsOneWidget);
        // Carte du vote solennel : languette, jour en grand, titre court.
        expect(find.text('Vote solennel'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('Novembre · mardi 15 h'), findsOneWidget);
        expect(find.text("Budget de l'État 2027"), findsOneWidget);
        // Cartes des décisions : date, résultat, chiffres, titre court.
        expect(find.text('13 oct.'), findsOneWidget);
        expect(find.text('Adopté'), findsOneWidget);
        expect(find.text('503'), findsOneWidget);
        expect(find.text('Juges des violences sexuelles'), findsOneWidget);
        expect(find.text('Rejeté'), findsOneWidget);
        expect(find.text('Motion sur le même texte'), findsNothing);
        // Pas de carte « En débat » (#77).
        expect(find.text('En débat'), findsNothing);
        expect(find.text('Texte en débat'), findsNothing);
        // Les sièges des deux décisions affichées.
        expect(find.byType(HemicycleSeats), findsNWidgets(2));
        expect(find.byType(VoteArc), findsNothing);
        expect(
          requested.map((u) => u.path),
          containsAll([
            '/v1/decisions/VTANR5L17V8706.json',
            '/v1/decisions/VTANR5L17V8610.json',
          ]),
        );
        // La carte suivante dépasse de 28 points à droite.
        final title = tester.getTopLeft(
          find.text('Juges des violences sexuelles'),
        );
        expect(title.dx, 390 - deckPeek + 22);
        // Les cartes, entre la date et le bouton.
        expect(
          tester.getTopLeft(find.text('Vote solennel')).dy,
          greaterThan(
            tester.getBottomLeft(find.text('Vendredi 23 octobre')).dy,
          ),
        );
        expect(
          tester.getBottomLeft(find.text("Budget de l'État 2027")).dy,
          lessThan(tester.getTopLeft(find.text('Toutes les décisions')).dy),
        );
        expect(tester.takeException(), isNull);

        await expectLater(
          find.byType(HomePage),
          matchesGoldenFile('goldens/accueil-$theme.png'),
        );
      });

      testWidgets('carte décision : défile, puis ouvre le détail', (
        tester,
      ) async {
        await _pumpHome(tester, brightness: brightness);
        await _swipe(tester);

        // La carte suivante s'aligne sur la marge.
        expect(
          tester.getTopLeft(find.text('Juges des violences sexuelles')).dx,
          20 + 22,
        );
        expect(
          find.bySemanticsLabel(
            RegExp('^Adopté, 503 pour, 0 contre, 67 abstentions'),
          ),
          findsOneWidget,
        );
        await expectLater(
          find.byType(HomePage),
          matchesGoldenFile('goldens/accueil-carte2-$theme.png'),
        );

        await tester.tap(find.text('Juges des violences sexuelles'));
        await tester.pumpAndSettle();
        expect(find.byType(DecisionDetailPage), findsOneWidget);
        expect(
          tester.widget<DecisionDetailPage>(find.byType(DecisionDetailPage)).id,
          'VTANR5L17V8706',
        );
      });
    });
  }

  testWidgets('sans fichier de détail : l\'arc de l\'index', (tester) async {
    await _pumpHome(tester, withDetails: false);
    expect(find.byType(HemicycleSeats), findsNothing);
    expect(find.byType(VoteArc), findsNWidgets(2));
    expect(find.text('Adopté'), findsOneWidget);
    expect(find.text('503'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la carte vote solennel est un lien vers le dossier', (
    tester,
  ) async {
    await _pumpHome(tester);
    expect(
      tester.getSemantics(
        find.bySemanticsLabel(RegExp('^Vote solennel, Mardi 3 novembre')),
      ),
      isSemantics(isLink: true, hasTapAction: true),
    );
  });

  testWidgets('« Toutes les décisions » ouvre la liste, retour possible', (
    tester,
  ) async {
    await _pumpHome(tester);
    await tester.tap(find.text('Toutes les décisions'));
    await tester.pumpAndSettle();

    expect(find.byType(DecisionListPage), findsOneWidget);
    expect(find.text('Décisions'), findsOneWidget);
    expect(find.text('Motion sur le même texte'), findsOneWidget);
    expect(find.text('En débat'), findsNothing);

    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    expect(find.text('Vendredi 23 octobre'), findsOneWidget);
  });

  testWidgets('index vide : message, bouton toujours là', (tester) async {
    await _pumpHome(
      tester,
      index: DecisionIndex(generatedAt: _now, decisions: const []),
    );
    expect(
      find.text('Aucune décision publiée pour le moment.'),
      findsOneWidget,
    );
    expect(find.text('Toutes les décisions'), findsOneWidget);
  });
}
