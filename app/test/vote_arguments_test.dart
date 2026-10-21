import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:votedujour/src/decision_detail/decision_detail_page.dart';
import 'package:votedujour/src/decision_detail/decision_detail_repository.dart';
import 'package:votedujour/src/decision_detail/vote_arguments.dart';
import 'package:votedujour/src/theme.dart';

final _summary = DecisionSummary(
  id: 'VTANR5L17V8706',
  numero: 8706,
  type: DecisionType.ensembleTexte,
  status: DecisionStatus.confirmee,
  result: VoteResult.adopte,
  date: DateTime.utc(2026, 10, 13),
  officialTitle:
      "l'ensemble de la proposition de loi visant à renforcer la protection "
      'des enfants victimes de violences.',
  sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/8706',
  shortTitle: 'Protection des enfants victimes',
);

const _groups = [
  GroupVoteDetail(
    organeRef: 'PO845419',
    name: 'Socialistes et apparentés',
    abbreviation: 'SOC',
    position: GroupPosition.pour,
    count: VoteCount(pour: 68, contre: 0, abstentions: 0, nonVotants: 0),
  ),
  GroupVoteDetail(
    organeRef: 'PO845413',
    name: 'La France insoumise',
    abbreviation: 'LFI-NFP',
    position: GroupPosition.abstention,
    count: VoteCount(pour: 4, contre: 0, abstentions: 66, nonVotants: 0),
  ),
];

// Séance du 13 octobre 2026 (scrutin 8706) : aucun groupe contre.
final _arguments = DecisionArguments(
  promptVersion: 1,
  source: ArgumentsSource(
    date: DateTime.utc(2026, 10, 13),
    url: 'https://www.assemblee-nationale.fr/dyn/17/comptes-rendus/seance/1',
  ),
  pour: const [
    GroupArgument(
      group: 'SOC',
      text: "L'impunité reste massive : 86 % des plaintes sont classées.",
    ),
    GroupArgument(
      group: 'NI',
      text: 'Les témoins qui signalent des violences seront mieux protégés.',
    ),
  ],
  abstention: const [
    GroupArgument(group: 'LFI-NFP', text: 'Le texte a été affaibli en séance.'),
  ],
);

Future<void> _pumpDetail(
  WidgetTester tester,
  DecisionDetail detail, {
  Brightness brightness = Brightness.light,
}) async {
  final client = MockClient(
    (request) async =>
        http.Response.bytes(utf8.encode(jsonEncode(detail.toJson())), 200),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness),
      home: DecisionDetailPage(
        id: _summary.id,
        repository: DecisionDetailRepository(
          baseUrl: 'https://example.test',
          client: client,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('arguments pour et d\'abstention (${brightness.name})', (
      tester,
    ) async {
      await _pumpDetail(
        tester,
        DecisionDetail(
          decision: _summary,
          groups: _groups,
          arguments: _arguments,
        ),
        brightness: brightness,
      );
      await tester.scrollUntilVisible(
        find.textContaining('Séance du', findRichText: true),
        200,
      );
      expect(find.text('Pourquoi ils ont voté ainsi'), findsOneWidget);
      // Titres des cartes (« Pour » est aussi une rangée de « Qui a voté
      // quoi »).
      Finder side(String label) => find.descendant(
        of: find.byType(VoteArguments),
        matching: find.text(label),
      );
      expect(side('Pour'), findsOneWidget);
      expect(side('Abstention'), findsOneWidget);
      // Camp vide : pas de carte.
      expect(side('Contre'), findsNothing);
      expect(
        find.textContaining("SOC L'impunité reste massive", findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'LFI-NFP Le texte a été affaibli',
          findRichText: true,
        ),
        findsOneWidget,
      );
      // Sans logo embarqué : vignette à sigle.
      expect(find.text('NI'), findsOneWidget);
      expect(
        find.textContaining(
          'Séance du 13 oct. (compte rendu)',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('argument contre seul : une seule carte', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoteArguments(
            DecisionArguments(
              promptVersion: 1,
              source: _arguments.source,
              contre: const [
                GroupArgument(group: 'RN', text: 'Le texte coûte trop cher.'),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Contre'), findsOneWidget);
    expect(find.text('Pour'), findsNothing);
    expect(find.text('Abstention'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('sans arguments : pas de section', (tester) async {
    // Écran assez haut pour construire toute la page.
    tester.view.physicalSize = const Size(1200, 9000);
    addTearDown(tester.view.resetPhysicalSize);
    await _pumpDetail(
      tester,
      DecisionDetail(decision: _summary, groups: _groups),
    );
    expect(find.text('Voir le scrutin'), findsOneWidget);
    expect(find.text('Qui a voté quoi'), findsOneWidget);
    expect(find.text('Pourquoi ils ont voté ainsi'), findsNothing);
    expect(
      find.textContaining('compte rendu', findRichText: true),
      findsNothing,
    );
  });
}
