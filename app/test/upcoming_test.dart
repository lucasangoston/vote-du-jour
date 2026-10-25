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
import 'package:votedujour/src/upcoming.dart';

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

void main() {
  test('les points à venir dans l\'ordre chronologique, ordre de l\'index '
      'à heure égale', () {
    expect(upcomingToShow(_agenda, now: _now).map((u) => u.id), [
      // Discussion du jour, puis le 27/10 (vote avant discussion, comme dans
      // l'index), puis le vote du 3/11.
      'PT53278',
      'PT53289',
      'PT53435',
      'PT53449',
    ]);
  });

  test('rien sans point à venir', () {
    expect(upcomingToShow(null, now: _now), isEmpty);
    expect(upcomingToShow(const [], now: _now), isEmpty);
  });

  test('rien quand tous les points sont passés (index hors ligne)', () {
    expect(
      upcomingToShow([
        _item(
          'PT1',
          UpcomingKind.voteSolennel,
          DateTime.utc(2026, 10, 20, 14),
          'Texte voté hier',
        ),
      ], now: _now),
      isEmpty,
    );
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

    testWidgets('plus de section « À venir » (maquette `liste`, #89)', (
      tester,
    ) async {
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

      expect(find.text("L'ensemble du projet de loi exemple."), findsOneWidget);
      expect(find.text('À venir'), findsNothing);
      expect(find.text('Texte voté bientôt'), findsNothing);
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
