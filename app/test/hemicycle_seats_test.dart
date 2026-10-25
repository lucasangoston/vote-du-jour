import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:votedujour/src/decision_detail/decision_detail_page.dart';
import 'package:votedujour/src/skeleton.dart';
import 'package:votedujour/src/decision_detail/decision_detail_repository.dart';
import 'package:votedujour/src/decision_detail/who_voted_what.dart';
import 'package:votedujour/src/hemicycle/hemicycle_places.dart';
import 'package:votedujour/src/hemicycle/hemicycle_seats.dart';
import 'package:votedujour/src/hemicycle/vote_arc.dart';
import 'package:votedujour/src/theme.dart';

/// Fichiers de détail des scrutins 8706 (adopté) et 8610 (rejeté), tels que
/// publiés depuis #71 : groupes avec leur couleur, sièges du scrutin. Faits
/// depuis les données des maquettes (`design/maquettes/data/`).
DecisionDetail _fixture(int numero) => DecisionDetail.fromJson(
  jsonDecode(File('test/fixtures/detail_$numero.json').readAsStringSync()),
);

const _rn = 'PO845401';
const _lfi = 'PO845413';
const _soc = 'PO845419';

/// Ouvre le détail de [detail] (servi par un faux serveur) sur un écran de
/// 390 × 844.
Future<void> _pumpDetail(
  WidgetTester tester,
  DecisionDetail detail, {
  Brightness brightness = Brightness.light,
}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = MockClient(
    (request) async =>
        http.Response.bytes(utf8.encode(jsonEncode(detail.toJson())), 200),
  );
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(brightness),
      home: DecisionDetailPage(
        id: detail.decision.id,
        repository: DecisionDetailRepository(
          baseUrl: 'https://example.test',
          client: client,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

HemicycleSeats _hemicycle(WidgetTester tester) =>
    tester.widget<HemicycleSeats>(find.byType(HemicycleSeats));

double _meanX(List<SeatMark> marks, String group) {
  final xs = [
    for (final m in marks)
      if (m.group == group) m.center.dx,
  ];
  return xs.reduce((a, b) => a + b) / xs.length;
}

void main() {
  group('seatMarks', () {
    final d8706 = _fixture(8706);
    final d8610 = _fixture(8610);

    test('574 places, forme selon le vote, absents estompés à 28 %', () {
      final marks = seatMarks(
        seats: d8610.seats!,
        groups: d8610.groups,
        brightness: Brightness.light,
      );
      expect(marks, hasLength(574));
      int count(SeatShape shape, double opacity) =>
          marks.where((m) => m.shape == shape && m.opacity == opacity).length;
      expect(count(SeatShape.disc, 1), 151);
      expect(count(SeatShape.ring, 1), 187);
      expect(count(SeatShape.dot, 1), 0);
      // 235 absents et un non-votant.
      expect(count(SeatShape.disc, seatOffOpacity), 236);
      expect(seatOffOpacity, 0.28);

      final abstentions = seatMarks(
        seats: d8706.seats!,
        groups: d8706.groups,
        brightness: Brightness.light,
      ).where((m) => m.shape == SeatShape.dot);
      expect(abstentions, hasLength(67));
    });

    test('dôme vu du perchoir : LFI-NFP à gauche, RN à droite', () {
      final marks = seatMarks(
        seats: d8706.seats!,
        groups: d8706.groups,
        brightness: Brightness.light,
      );
      final center = hemicyclePlan.center.dx;
      expect(_meanX(marks, _lfi), lessThan(center));
      expect(_meanX(marks, _rn), greaterThan(center));
      final groupsByX = {
        for (final g in d8706.groups) g.organeRef: _meanX(marks, g.organeRef),
      };
      final leftmost = groupsByX.entries.reduce(
        (a, b) => a.value < b.value ? a : b,
      );
      final rightmost = groupsByX.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );
      expect(leftmost.key, _lfi);
      expect(rightmost.key, _rn);
    });

    test('couleurs officielles de jour, contour des couleurs claires', () {
      final marks = seatMarks(
        seats: d8706.seats!,
        groups: d8706.groups,
        brightness: Brightness.light,
      );
      final rn = marks.firstWhere((m) => m.group == _rn);
      expect(rn.color, const Color(0xFF313567));
      expect(rn.outline, isNull);
      // SOC (#F5B4CE) est sous 3:1 sur le blanc : contour 35 % plus sombre.
      final soc = marks.firstWhere((m) => m.group == _soc);
      expect(soc.color, const Color(0xFFF5B4CE));
      expect(
        soc.outline,
        Color.lerp(const Color(0xFFF5B4CE), const Color(0xFF000000), 0.35),
      );
      final outlined = {
        for (final g in d8706.groups)
          if (seatOutline(groupColor(g.color), Brightness.light) != null)
            g.abbreviation,
      };
      // NI (#8D949A) tient 3,07:1, juste au-dessus du seuil, comme dans les
      // maquettes.
      expect(outlined, {'HOR', 'LIOT', 'SOC', 'DR', 'EcoS', 'Dem'});
    });

    test('nuit : couleurs éclaircies de 30 % vers le blanc, sans contour', () {
      final marks = seatMarks(
        seats: d8706.seats!,
        groups: d8706.groups,
        brightness: Brightness.dark,
      );
      final rn = marks.firstWhere((m) => m.group == _rn);
      expect(
        rn.color,
        Color.lerp(const Color(0xFF313567), const Color(0xFFFFFFFF), 0.3),
      );
      expect(marks.where((m) => m.outline != null), isEmpty);
    });

    test('groupe allumé : les autres sièges s\'estompent', () {
      final marks = seatMarks(
        seats: d8706.seats!,
        groups: d8706.groups,
        brightness: Brightness.light,
        lit: _rn,
      );
      expect(
        marks.where((m) => m.opacity != seatDimmedOpacity).map((m) => m.group),
        everyElement(_rn),
      );
      expect(
        marks.where((m) => m.group == _rn && m.opacity == 1),
        hasLength(121),
      );
    });

    test('couleur absente ou malformée : gris des non-inscrits', () {
      expect(groupColor(null), fallbackGroupColor);
      expect(groupColor('#12'), fallbackGroupColor);
      expect(groupColor('#C00D0D'), const Color(0xFFC00D0D));
    });

    test('place inconnue du plan : pas d\'hémicycle', () {
      expect(canDrawSeats(d8706.seats), isTrue);
      expect(canDrawSeats(null), isFalse);
      expect(canDrawSeats(const []), isFalse);
      expect(hemicyclePlaces.containsKey(4), isFalse);
      expect(
        canDrawSeats([
          ...d8706.seats!,
          const HemicycleSeat(place: 4, group: _rn, vote: SeatVote.pour),
        ]),
        isFalse,
      );
    });

    test('libellé pour les lecteurs d\'écran', () {
      expect(
        hemicycleSeatsLabel(VoteResult.adopte, d8706.count!.tally),
        'Adopté, 503 pour, 0 contre, 67 abstentions',
      );
      expect(
        hemicycleSeatsLabel(VoteResult.rejete, d8610.count!.tally),
        'Rejeté, 151 pour, 187 contre, 0 abstentions',
      );
    });
  });

  testWidgets(
    'squelette pendant le chargement, jamais l’arc puis l’hémicycle',
    (tester) async {
      final detail = _fixture(8706);
      final answer = Completer<http.Response>();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: DecisionDetailPage(
            id: detail.decision.id,
            summary: detail.decision,
            repository: DecisionDetailRepository(
              baseUrl: 'https://example.test',
              client: MockClient((_) => answer.future),
            ),
          ),
        ),
      );
      await tester.pump();
      // Le résumé de la liste est connu, mais on n'affiche ni arc ni titre :
      // tout l'écran est en squelette.
      expect(find.byType(DetailSkeleton), findsOneWidget);
      expect(find.byType(VoteArc), findsNothing);
      expect(find.byType(HemicycleSeats), findsNothing);
      expect(
        find.bySemanticsLabel('Chargement de la décision'),
        findsOneWidget,
      );

      answer.complete(
        http.Response.bytes(utf8.encode(jsonEncode(detail.toJson())), 200),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DetailSkeleton), findsNothing);
      expect(find.byType(HemicycleSeats), findsOneWidget);
    },
  );

  group('sièges sans vote', () {
    test('absents et non-votants comptés, dits en clair', () {
      expect(noVoteNote(_fixture(8706).seats!), '4 absents');
      expect(noVoteNote(_fixture(8610).seats!), '236 absents');
    });

    test('rien quand tout le monde a voté, singulier pour un seul', () {
      const p = HemicycleSeat(place: 1, group: 'PO1', vote: SeatVote.pour);
      const x = HemicycleSeat(place: 2, group: 'PO1', vote: SeatVote.absent);
      expect(noVoteNote([p]), isNull);
      expect(noVoteNote([p, x]), '1 absent');
    });

    testWidgets('le détail dit combien sont absents', (tester) async {
      await _pumpDetail(tester, _fixture(8610), brightness: Brightness.dark);
      expect(find.text('236 absents'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  for (final brightness in Brightness.values) {
    final theme = brightness == Brightness.light ? 'jour' : 'nuit';

    group('détail aux places réelles ($theme)', () {
      testWidgets('8706 : hémicycle, résultat dessous, chiffres', (
        tester,
      ) async {
        await _pumpDetail(tester, _fixture(8706), brightness: brightness);

        expect(find.byType(HemicycleSeats), findsOneWidget);
        expect(find.byType(VoteArc), findsNothing);
        expect(
          find.bySemanticsLabel('Adopté, 503 pour, 0 contre, 67 abstentions'),
          findsOneWidget,
        );
        // Le résultat sous l'hémicycle, jamais dans le creux.
        expect(
          tester.getTopLeft(find.text('Adopté')).dy,
          greaterThan(tester.getBottomLeft(find.byType(HemicycleSeats)).dy),
        );
        expect(find.text('503'), findsOneWidget);
        expect(find.text('abstentions'), findsOneWidget);
        // Ni repères, ni sigles autour, ni ligne des votants.
        expect(find.text('Gauche'), findsNothing);
        expect(find.textContaining('votants'), findsNothing);
        expect(tester.takeException(), isNull);

        await expectLater(
          find.byType(DecisionDetailPage),
          matchesGoldenFile('goldens/detail-8706-$theme.png'),
        );
      });

      testWidgets('8610 rejeté', (tester) async {
        await _pumpDetail(tester, _fixture(8610), brightness: brightness);
        expect(
          find.bySemanticsLabel('Rejeté, 151 pour, 187 contre, 0 abstentions'),
          findsOneWidget,
        );
        expect(find.text('Rejeté'), findsOneWidget);
        expect(find.text('187'), findsOneWidget);
        await expectLater(
          find.byType(DecisionDetailPage),
          matchesGoldenFile('goldens/detail-8610-$theme.png'),
        );
      });

      testWidgets('tap sur une tuile : seuls les sièges du groupe restent '
          'pleins', (tester) async {
        await _pumpDetail(tester, _fixture(8706), brightness: brightness);
        expect(_hemicycle(tester).lit, isNull);

        final rn = find.widgetWithText(GroupTile, 'RN');
        await tester.scrollUntilVisible(rn, 300);
        // La tuile entière à l'écran, pas seulement son bord.
        await tester.ensureVisible(rn);
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel('RN, pour, montrer ses sièges'),
          findsOneWidget,
        );
        expect(
          tester.getSemantics(rn),
          isSemantics(isButton: true, isSelected: false),
        );
        await tester.tap(rn);
        await tester.pumpAndSettle();

        // L'hémicycle revient à l'écran, RN allumé.
        expect(find.byType(HemicycleSeats).hitTestable(), findsOneWidget);
        final seats = _hemicycle(tester);
        expect(seats.lit, _rn);
        final marks = seatMarks(
          seats: seats.seats,
          groups: seats.groups,
          brightness: brightness,
          lit: seats.lit,
        );
        expect(
          marks.where((m) => m.opacity > seatDimmedOpacity).map((m) => m.group),
          everyElement(_rn),
        );

        // La tuile choisie est annoncée comme telle.
        await tester.scrollUntilVisible(rn, 300);
        await tester.ensureVisible(rn);
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(rn),
          isSemantics(isButton: true, isSelected: true),
        );

        // Un second tap rallume tout l'hémicycle.
        await tester.tap(rn);
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(rn),
          isSemantics(isButton: true, isSelected: false),
        );
        await tester.scrollUntilVisible(find.byType(HemicycleSeats), -300);
        expect(_hemicycle(tester).lit, isNull);
      });
    });
  }

  testWidgets('groupe allumé (golden)', (tester) async {
    final detail = _fixture(8706);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              child: HemicycleSeats(
                seats: detail.seats!,
                groups: detail.groups,
                result: detail.decision.result,
                count: detail.count!.tally,
                width: 340,
                lit: _soc,
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(HemicycleSeats),
      matchesGoldenFile('goldens/hemicycle-8706-soc-jour.png'),
    );
  });

  testWidgets('détail sans sièges : arc actuel, vignettes sans bouton', (
    tester,
  ) async {
    final detail = _fixture(8706).withSeats(null);
    await _pumpDetail(tester, detail);

    expect(find.byType(HemicycleSeats), findsNothing);
    expect(find.byType(VoteArc), findsOneWidget);
    expect(
      find.bySemanticsLabel('Adopté : 503 pour, 0 contre, 67 abstentions'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('RN'), 300);
    expect(find.bySemanticsLabel(RegExp('montrer ses sièges')), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('^Rassemblement National : Pour')),
      findsOneWidget,
    );
  });

  testWidgets('place inconnue du plan : arc actuel', (tester) async {
    final d8706 = _fixture(8706);
    final detail = d8706.withSeats([
      ...d8706.seats!,
      const HemicycleSeat(place: 4, group: _rn, vote: SeatVote.absent),
    ]);
    await _pumpDetail(tester, detail);
    expect(find.byType(HemicycleSeats), findsNothing);
    expect(find.byType(VoteArc), findsOneWidget);
  });
}
