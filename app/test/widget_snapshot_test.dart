import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:votedujour/src/home_widget/widget_snapshot.dart';

DecisionSummary _decision(int numero, VoteResult result, DateTime date) =>
    DecisionSummary(
      id: 'VTANR5L17V$numero',
      numero: numero,
      type: DecisionType.ensembleTexte,
      status: DecisionStatus.confirmee,
      result: result,
      date: date,
      officialTitle: "l'ensemble du projet de loi n° $numero.",
      sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/$numero',
    );

void main() {
  final index = DecisionIndex(
    generatedAt: DateTime.utc(2026, 10, 17, 10),
    decisions: [
      _decision(8710, VoteResult.adopte, DateTime.utc(2026, 10, 15)),
      _decision(8709, VoteResult.rejete, DateTime.utc(2026, 10, 14)),
      _decision(8708, VoteResult.adopte, DateTime.utc(2026, 10, 13)),
      _decision(8707, VoteResult.adopte, DateTime.utc(2026, 10, 12)),
    ],
  );

  test('garde les trois décisions les plus récentes, prêtes à afficher', () {
    final snapshot = WidgetSnapshot.fromIndex(
      index,
      savedAt: DateTime.utc(2026, 10, 17, 11, 30),
    );

    expect(snapshot.toJson(), {
      'version': 1,
      'savedAt': '2026-10-17T11:30:00.000Z',
      'decisions': [
        {
          'id': 'VTANR5L17V8710',
          'result': 'adopte',
          'date': '2026-10-15',
          'title': "L'ensemble du projet de loi n° 8710.",
        },
        {
          'id': 'VTANR5L17V8709',
          'result': 'rejete',
          'date': '2026-10-14',
          'title': "L'ensemble du projet de loi n° 8709.",
        },
        {
          'id': 'VTANR5L17V8708',
          'result': 'adopte',
          'date': '2026-10-13',
          'title': "L'ensemble du projet de loi n° 8708.",
        },
      ],
    });
  });

  test('décision à main levée : la mention suit l\'étape', () {
    DecisionSummary mainLevee({String? stage}) => DecisionSummary(
      id: 'L17-VD234087DEC',
      voteMode: VoteMode.mainLevee,
      type: DecisionType.ensembleTexte,
      status: DecisionStatus.confirmee,
      result: VoteResult.adopte,
      date: DateTime.utc(2026, 10, 7),
      officialTitle: "projet de loi autorisant l'approbation de l'accord.",
      sourceUrl:
          'https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N54379',
      shortTitle: 'Accord multilatéral GloBE',
      stage: stage,
    );
    final snapshot = WidgetSnapshot.fromIndex(
      DecisionIndex(
        generatedAt: DateTime.utc(2026, 10, 17),
        decisions: [
          mainLevee(stage: "1re lecture à l'AN"),
          mainLevee(),
          index.decisions.first,
        ],
      ),
      savedAt: DateTime.utc(2026, 10, 17),
    );

    final json = jsonDecode(jsonEncode(snapshot.toJson()));
    expect((json as Map)['decisions'][0], {
      'id': 'L17-VD234087DEC',
      'result': 'adopte',
      'date': '2026-10-07',
      'title': 'Accord multilatéral GloBE',
      'stage': "1re lecture à l'AN · à main levée",
    });
    final read = WidgetSnapshot.tryFromJson(json)!;
    expect(read.decisions.map((d) => d.stage), [
      "1re lecture à l'AN · à main levée",
      'À main levée',
      null,
    ]);
  });

  test('relit ce qu\'il écrit, champs optionnels compris', () {
    final snapshot = WidgetSnapshot(
      savedAt: DateTime.utc(2026, 10, 17),
      decisions: [
        WidgetDecision(
          id: 'VTANR5L17V8710',
          result: VoteResult.rejete,
          date: DateTime.utc(2026, 10, 15),
          title: 'Budget de la Sécurité sociale',
          stage: "1re lecture à l'AN",
          explanation: 'La première partie est rejetée, le texte tombe.',
        ),
      ],
    );

    final json = jsonDecode(jsonEncode(snapshot.toJson()));
    final read = WidgetSnapshot.tryFromJson(json)!;

    expect(read.toJson(), snapshot.toJson());
    expect(read.decisions.single.stage, "1re lecture à l'AN");
  });

  test('ignore une autre version et les décisions malformées', () {
    expect(WidgetSnapshot.tryFromJson({'version': 2}), isNull);

    final read = WidgetSnapshot.tryFromJson({
      'version': 1,
      'savedAt': '2026-10-17T00:00:00.000Z',
      'decisions': [
        {'id': 'x', 'result': 'inconnu', 'date': '2026-10-15', 'title': 't'},
        {'id': 'y', 'result': 'adopte', 'date': '2026-10-15', 'title': 't'},
      ],
    })!;

    expect(read.decisions.map((d) => d.id), ['y']);
  });
}
