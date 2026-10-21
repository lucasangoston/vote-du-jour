import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:votedujour/src/decision_list_page.dart';
import 'package:votedujour/src/decisions_repository.dart';
import 'package:votedujour/src/relative_date.dart';
import 'package:votedujour/src/theme.dart';
import 'package:votedujour/src/upcoming_section.dart';

/// Points de l'ordre du jour publié le 21/10/2026 (#52).
const _dossierPlfss =
    'https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N54951';
const _dossierPlf =
    'https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N54629';

UpcomingItem _item(
  String id,
  UpcomingKind kind,
  DateTime startsAt,
  String shortTitle, {
  bool inProgress = false,
  String? dossierUrl,
}) => UpcomingItem(
  id: id,
  kind: kind,
  startsAt: startsAt,
  seanceRef: 'RUANR5L17S2027IDS$id',
  label: shortTitle,
  shortTitle: shortTitle,
  inProgress: inProgress,
  dossierUrl: dossierUrl,
);

final _now = DateTime.utc(2026, 10, 21, 10);

final _agenda = [
  // Dans l'index, le vote du 3/11 avant la discussion du jour : l'app trie.
  _item(
    'PT53449',
    UpcomingKind.voteSolennel,
    DateTime.utc(2026, 11, 3, 14),
    'Projet de loi de finances pour 2027 (première partie)',
    dossierUrl: _dossierPlf,
  ),
  _item(
    'PT53278',
    UpcomingKind.discussion,
    DateTime.utc(2026, 10, 21, 19, 30),
    'Projet de loi de financement de la sécurité sociale pour 2027',
    inProgress: true,
    dossierUrl: _dossierPlfss,
  ),
  _item(
    'PT53289',
    UpcomingKind.voteSolennel,
    DateTime.utc(2026, 10, 27, 14),
    'Projet de loi de financement de la sécurité sociale pour 2027',
    dossierUrl: _dossierPlfss,
  ),
  _item(
    'PT53435',
    UpcomingKind.discussion,
    DateTime.utc(2026, 10, 27, 14),
    'Projet de loi de finances pour 2027',
    inProgress: true,
    dossierUrl: _dossierPlf,
  ),
];

Future<void> _pumpSection(
  WidgetTester tester,
  List<UpcomingItem>? items,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: UpcomingSection(items: items, now: _now),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'affiche les 3 premiers points dans l\'ordre chronologique, jour, heure '
    'de Paris, badge et mention',
    (tester) async {
      await _pumpSection(tester, _agenda);

      expect(find.text('À venir'), findsOneWidget);
      // Discussion du jour : 19 h 30 UTC, 21 h 30 à Paris (heure d'été).
      expect(find.text("Aujourd'hui"), findsOneWidget);
      expect(find.text('à partir de 21h30'), findsOneWidget);
      expect(find.text('En discussion'), findsNWidgets(2));
      // Vote solennel du 27/10 : 14 h UTC, 15 h à Paris (heure d'hiver).
      expect(find.text('Mardi 27 oct.'), findsNWidgets(2));
      expect(find.text('à partir de 15h'), findsNWidgets(2));
      expect(find.text('Vote solennel'), findsOneWidget);
      // Le 4e point (3/11) attend « Tout voir ».
      expect(find.text('Mardi 3 nov.'), findsNothing);
      expect(find.text('Tout voir'), findsOneWidget);

      final titles = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .where((t) => t != null && t.startsWith('Projet'))
          .toList();
      expect(titles, [
        'Projet de loi de financement de la sécurité sociale pour 2027',
        'Projet de loi de financement de la sécurité sociale pour 2027',
        'Projet de loi de finances pour 2027',
      ]);
    },
  );

  testWidgets('« Tout voir » déplie la liste complète', (tester) async {
    await _pumpSection(tester, _agenda);
    await tester.tap(find.text('Tout voir'));
    await tester.pump();

    expect(find.text('Tout voir'), findsNothing);
    expect(find.text('Mardi 3 nov.'), findsOneWidget);
    expect(
      find.text('Projet de loi de finances pour 2027 (première partie)'),
      findsOneWidget,
    );
    expect(find.text('Vote solennel'), findsNWidgets(2));
  });

  testWidgets('pas de « Tout voir » avec 3 points ou moins', (tester) async {
    await _pumpSection(tester, _agenda.take(3).toList());
    expect(find.text('À venir'), findsOneWidget);
    expect(find.text('Tout voir'), findsNothing);
  });

  testWidgets('un point lu au lecteur d\'écran est un lien complet', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpSection(tester, [_agenda[0]]);
    expect(
      find.bySemanticsLabel(
        'Mardi 3 novembre, à partir de 15h, vote solennel, '
        'Projet de loi de finances pour 2027 (première partie)',
      ),
      findsOneWidget,
    );
    final heading = tester.getSemantics(find.text('À venir'));
    expect(heading.flagsCollection.isHeader, isTrue);
    handle.dispose();
  });

  testWidgets('rien sans point à venir', (tester) async {
    for (final items in [null, <UpcomingItem>[]]) {
      await _pumpSection(tester, items);
      expect(find.text('À venir'), findsNothing);
      expect(find.byType(UpcomingRow), findsNothing);
    }
  });

  testWidgets('rien quand tous les points sont passés (index hors ligne)', (
    tester,
  ) async {
    await _pumpSection(tester, [
      _item(
        'PT1',
        UpcomingKind.voteSolennel,
        DateTime.utc(2026, 10, 20, 14),
        'Texte voté hier',
      ),
    ]);
    expect(find.text('À venir'), findsNothing);
  });

  group('dans la liste', () {
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

    testWidgets('section avant les décisions', (tester) async {
      final soon = DateTime.now().toUtc().add(const Duration(days: 2));
      await pumpList(tester, {
        'schemaVersion': 1,
        'generatedAt': '2026-10-21T10:00:00.000Z',
        'decisions': [decision],
        'upcoming': [
          _item(
            'PT1',
            UpcomingKind.voteSolennel,
            soon,
            'Texte voté bientôt',
          ).toJson(),
        ],
      });
      await tester.pumpAndSettle();

      expect(find.text('Texte voté bientôt'), findsOneWidget);
      expect(find.text('Vote solennel'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('À venir')).dy,
        lessThan(
          tester
              .getTopLeft(find.text("L'ensemble du projet de loi exemple."))
              .dy,
        ),
      );
    });

    testWidgets('ancien index sans `upcoming` : rien', (tester) async {
      await pumpList(tester, {
        'schemaVersion': 1,
        'generatedAt': '2026-10-21T10:00:00.000Z',
        'decisions': [decision],
      });
      await tester.pumpAndSettle();

      expect(find.text("L'ensemble du projet de loi exemple."), findsOneWidget);
      expect(find.text('À venir'), findsNothing);
    });
  });

  group('dates de l\'ordre du jour', () {
    test('heure de Paris, heures d\'été et d\'hiver', () {
      // Passage à l'heure d'hiver le dimanche 25/10/2026 à 1 h UTC.
      expect(parisHourLabel(DateTime.utc(2026, 10, 25, 0, 59)), '2h59');
      expect(parisHourLabel(DateTime.utc(2026, 10, 25, 1)), '2h');
      // Passage à l'heure d'été le dimanche 29/03/2026 à 1 h UTC.
      expect(parisHourLabel(DateTime.utc(2026, 3, 29, 0, 59)), '1h59');
      expect(parisHourLabel(DateTime.utc(2026, 3, 29, 1)), '3h');
      // Le jour suit Paris : 23 h 30 UTC un 31 décembre, déjà le 1er janvier.
      expect(
        parisDay(DateTime.utc(2026, 12, 31, 23, 30)),
        DateTime.utc(2027, 1, 1),
      );
    });

    test('jour relatif ou date courte', () {
      expect(
        upcomingDayLabel(DateTime.utc(2026, 10, 21, 19), now: _now),
        "Aujourd'hui",
      );
      expect(
        upcomingDayLabel(DateTime.utc(2026, 10, 22, 13), now: _now),
        'Demain',
      );
      expect(
        upcomingDayLabel(DateTime.utc(2026, 10, 27, 14), now: _now),
        'Mardi 27 oct.',
      );
      expect(
        upcomingDayLabel(DateTime.utc(2026, 11, 1, 14), now: _now, long: true),
        'Dimanche 1er novembre',
      );
    });
  });
}
