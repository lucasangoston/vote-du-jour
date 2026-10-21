import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:votedujour/src/decision_list_page.dart';
import 'package:votedujour/src/decisions_repository.dart';
import 'package:votedujour/src/in_debate_section.dart';
import 'package:votedujour/src/theme.dart';

/// Texte en débat le lundi 19/10/2026 au soir (scrutins réels du PLF 2027),
/// avec deux articles plus anciens pour dépasser le maximum affiché.
DebatedArticle _article(String number, ArticleOutcome outcome, int scrutin) =>
    DebatedArticle(
      number: number,
      outcome: outcome,
      date: DateTime.utc(2026, 10, 19),
      scrutinRef: 'VTANR5L17V$scrutin',
    );

final _plf = InDebate(
  dossierRef: 'DLR5L17N54629',
  shortTitle: 'Budget de l\'État 2027',
  dossierUrl:
      'https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N54629',
  seanceRef: 'RUANR5L17S2027IDS30951',
  startsAt: DateTime.utc(2026, 10, 19, 19, 30),
  articles: [
    _article('40', ArticleOutcome.rejete, 8892),
    _article('39', ArticleOutcome.supprime, 8889),
    _article('38', ArticleOutcome.adopte, 8888),
    _article('37', ArticleOutcome.supprime, 8887),
    _article('35', ArticleOutcome.supprime, 8883),
    _article('5', ArticleOutcome.adopte, 8876),
    _article('4', ArticleOutcome.adopte, 8818),
    _article('liminaire', ArticleOutcome.supprime, 8708),
  ],
);

InDebate _withArticles(InDebate d, List<DebatedArticle> articles) => InDebate(
  dossierRef: d.dossierRef,
  shortTitle: d.shortTitle,
  dossierUrl: d.dossierUrl,
  seanceRef: d.seanceRef,
  startsAt: d.startsAt,
  articles: articles,
);

final _now = DateTime.utc(2026, 10, 19, 21);

Future<void> _pumpSection(
  WidgetTester tester,
  InDebate? inDebate, {
  DateTime? now,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildTheme(Brightness.light),
    home: Scaffold(
      body: SingleChildScrollView(
        child: InDebateSection(inDebate: inDebate, now: now ?? _now),
      ),
    ),
  ),
);

/// Texte affiché des articles (« Art. 40 rejeté »).
List<String> _articleTexts(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    if (t.textSpan?.toPlainText() case final text? when text.startsWith('Art.'))
      text,
];

void main() {
  testWidgets('titre court, 6 derniers articles avec leur sort, puis « +N »', (
    tester,
  ) async {
    await _pumpSection(tester, _plf);

    expect(find.text('En débat'), findsOneWidget);
    expect(find.text('Budget de l\'État 2027'), findsOneWidget);
    expect(_articleTexts(tester), [
      'Art. 40 rejeté',
      'Art. 39 supprimé',
      'Art. 38 adopté',
      'Art. 37 supprimé',
      'Art. 35 supprimé',
      'Art. 5 adopté',
    ]);
    expect(find.text('+2'), findsOneWidget);
    // Aucun chiffre de voix.
    expect(find.textContaining('voix'), findsNothing);
  });

  testWidgets('le sort porte la couleur du pour ou du contre', (tester) async {
    await _pumpSection(tester, _plf);
    final context = tester.element(find.text('En débat'));
    Color? colorOf(String text) {
      final rich = tester
          .widgetList<Text>(find.byType(Text))
          .firstWhere((t) => t.textSpan?.toPlainText() == text);
      final outcome = (rich.textSpan! as TextSpan).children!.last as TextSpan;
      return outcome.style?.color;
    }

    expect(colorOf('Art. 38 adopté'), context.colors.pour);
    expect(colorOf('Art. 40 rejeté'), context.colors.contre);
    expect(colorOf('Art. 39 supprimé'), context.colors.contre);
  });

  testWidgets('pas de « +N » avec 6 articles ou moins', (tester) async {
    await _pumpSection(
      tester,
      _withArticles(_plf, _plf.articles.take(2).toList()),
    );
    expect(_articleTexts(tester), ['Art. 40 rejeté', 'Art. 39 supprimé']);
    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets('lu au lecteur d\'écran : un lien complet', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpSection(tester, _plf);
    expect(
      find.bySemanticsLabel(
        'En débat : Budget de l\'État 2027. Article 40 rejeté, article 39 '
        'supprimé, article 38 adopté, article 37 supprimé, article 35 '
        'supprimé, article 5 adopté, et 2 autres articles votés',
      ),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.text('En débat')).flagsCollection.isHeader,
      isTrue,
    );
    handle.dispose();
  });

  testWidgets('rien sans texte en débat, sans article, ou après 7 jours', (
    tester,
  ) async {
    await _pumpSection(tester, null);
    expect(find.text('En débat'), findsNothing);

    await _pumpSection(tester, _withArticles(_plf, const []));
    expect(find.text('En débat'), findsNothing);

    await _pumpSection(tester, _plf, now: DateTime.utc(2026, 10, 26, 21));
    expect(find.text('En débat'), findsOneWidget);
    await _pumpSection(tester, _plf, now: DateTime.utc(2026, 10, 27, 21));
    expect(find.text('En débat'), findsNothing);
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

    testWidgets('sous « À venir », avant les décisions', (tester) async {
      final now = DateTime.now().toUtc();
      final inDebate = InDebate(
        dossierRef: _plf.dossierRef,
        shortTitle: _plf.shortTitle,
        dossierUrl: _plf.dossierUrl,
        seanceRef: _plf.seanceRef,
        startsAt: now.subtract(const Duration(hours: 2)),
        articles: _plf.articles.take(2).toList(),
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

      double top(Finder f) => tester.getTopLeft(f).dy;
      expect(top(find.text('À venir')), lessThan(top(find.text('En débat'))));
      expect(
        top(find.text('En débat')),
        lessThan(top(find.text("L'ensemble du projet de loi exemple."))),
      );
      expect(_articleTexts(tester), ['Art. 40 rejeté', 'Art. 39 supprimé']);
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
