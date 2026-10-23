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
          'voteMode': 'scrutin_public',
        },
        {
          'id': 'VTANR5L17V8709',
          'result': 'rejete',
          'date': '2026-10-14',
          'title': "L'ensemble du projet de loi n° 8709.",
          'voteMode': 'scrutin_public',
        },
        {
          'id': 'VTANR5L17V8708',
          'result': 'adopte',
          'date': '2026-10-13',
          'title': "L'ensemble du projet de loi n° 8708.",
          'voteMode': 'scrutin_public',
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
      'voteMode': 'main_levee',
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
          count: const VoteTally(pour: 144, contre: 199, abstentions: 5),
          voteMode: VoteMode.scrutinPublic,
          arc: const [
            HemicycleSegment(ArcPosition.contre, 199),
            HemicycleSegment(ArcPosition.abstention, 5),
            HemicycleSegment(ArcPosition.pour, 144),
          ],
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

  test('décompte et mode de vote : format fixé pour les widgets (#29)', () {
    final summary = DecisionSummary(
      id: 'VTANR5L17V8706',
      numero: 8706,
      type: DecisionType.ensembleTexte,
      status: DecisionStatus.confirmee,
      result: VoteResult.adopte,
      date: DateTime.utc(2026, 10, 13),
      officialTitle: 'Juges spécialisés',
      sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/8706',
      count: const VoteTally(pour: 503, contre: 0, abstentions: 67),
    );
    final json = jsonDecode(
      jsonEncode(WidgetDecision.fromSummary(summary).toJson()),
    );
    expect(json, {
      'id': 'VTANR5L17V8706',
      'result': 'adopte',
      'date': '2026-10-13',
      'title': 'Juges spécialisés',
      'count': {'pour': 503, 'contre': 0, 'abstentions': 67},
      'voteMode': 'scrutin_public',
    });
  });

  group('prochains votes solennels (#56)', () {
    UpcomingItem item(
      String id,
      UpcomingKind kind,
      DateTime startsAt,
      String shortTitle,
    ) => UpcomingItem(
      id: id,
      kind: kind,
      startsAt: startsAt,
      seanceRef: 'RUANR5L17S2027IDS30964',
      label: 'Vote solennel sur le projet de loi',
      shortTitle: shortTitle,
    );

    test('garde les votes solennels, du plus proche au plus lointain', () {
      final snapshot = WidgetSnapshot.fromIndex(
        index.withUpcoming([
          item(
            'PT3',
            UpcomingKind.voteSolennel,
            DateTime.utc(2026, 11, 3, 14),
            'budget 2027',
          ),
          item(
            'PT1',
            UpcomingKind.discussion,
            DateTime.utc(2026, 10, 22, 13),
            'Fin de vie',
          ),
          item(
            'PT2',
            UpcomingKind.voteSolennel,
            DateTime.utc(2026, 10, 27, 14),
            ' Budget de la Sécurité sociale pour 2027 ',
          ),
        ]),
        savedAt: DateTime.utc(2026, 10, 21),
      );

      final json = jsonDecode(jsonEncode(snapshot.toJson())) as Map;
      expect(json['upcomingVotes'], [
        {
          'id': 'PT2',
          'startsAt': '2026-10-27T14:00:00.000Z',
          'title': 'Budget de la Sécurité sociale pour 2027',
        },
        {
          'id': 'PT3',
          'startsAt': '2026-11-03T14:00:00.000Z',
          'title': 'Budget 2027',
        },
      ]);
      final read = WidgetSnapshot.tryFromJson(json)!;
      expect(read.toJson(), snapshot.toJson());
    });

    test('sans vote solennel, le champ est omis (format antérieur)', () {
      for (final upcoming in [
        null,
        <UpcomingItem>[],
        [
          item(
            'PT1',
            UpcomingKind.discussion,
            DateTime.utc(2026, 10, 22),
            'Fin de vie',
          ),
        ],
      ]) {
        final json = WidgetSnapshot.fromIndex(
          index.withUpcoming(upcoming),
          savedAt: DateTime.utc(2026, 10, 21),
        ).toJson();
        expect(json.containsKey('upcomingVotes'), isFalse);
      }
    });

    test('lit un ancien instantané et ignore les votes malformés', () {
      final old = WidgetSnapshot.tryFromJson({
        'version': 1,
        'savedAt': '2026-10-17T00:00:00.000Z',
        'decisions': <Object?>[],
      })!;
      expect(old.upcomingVotes, isEmpty);

      final read = WidgetSnapshot.tryFromJson({
        'version': 1,
        'savedAt': '2026-10-17T00:00:00.000Z',
        'decisions': <Object?>[],
        'upcomingVotes': [
          {'id': 'a', 'startsAt': 'demain', 'title': 't'},
          {'id': 'b', 'startsAt': '2026-10-27T14:00:00Z', 'title': ' '},
          {'id': 'c', 'startsAt': '2026-10-27T15:00:00+01:00', 'title': 't'},
          'd',
        ],
      })!;
      expect(read.upcomingVotes.map((u) => (u.id, u.startsAt)), [
        ('c', DateTime.utc(2026, 10, 27, 14)),
      ]);
      expect(
        WidgetSnapshot.tryFromJson({
          'version': 1,
          'savedAt': '2026-10-17T00:00:00.000Z',
          'decisions': <Object?>[],
          'upcomingVotes': 'aucun',
        })!.upcomingVotes,
        isEmpty,
      );
    });
  });

  test('lit un instantané antérieur à #29, sans décompte ni mode', () {
    final read = WidgetSnapshot.tryFromJson({
      'version': 1,
      'savedAt': '2026-10-17T00:00:00.000Z',
      'decisions': [
        {'id': 'y', 'result': 'adopte', 'date': '2026-10-15', 'title': 't'},
        {
          'id': 'z',
          'result': 'adopte',
          'date': '2026-10-15',
          'title': 't',
          'count': {'pour': 'beaucoup'},
          'voteMode': 'vote_electronique',
        },
      ],
    })!;
    expect(read.decisions.map((d) => (d.count, d.voteMode)), [
      (null, null),
      (null, null),
    ]);
  });

  test(
    "arc dans l'ordre de l'hémicycle : format fixé pour les widgets (#67)",
    () {
      final summary = DecisionSummary(
        id: 'VTANR5L17V8706',
        numero: 8706,
        type: DecisionType.ensembleTexte,
        status: DecisionStatus.confirmee,
        result: VoteResult.adopte,
        date: DateTime.utc(2026, 10, 13),
        officialTitle: 'Juges spécialisés',
        sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/8706',
        count: const VoteTally(pour: 503, contre: 0, abstentions: 67),
        arc: const [
          HemicycleSegment(ArcPosition.abstention, 66),
          HemicycleSegment(ArcPosition.pour, 382),
          HemicycleSegment(ArcPosition.abstention, 1),
          HemicycleSegment(ArcPosition.pour, 121),
        ],
      );
      final json =
          jsonDecode(jsonEncode(WidgetDecision.fromSummary(summary).toJson()))
              as Map<String, Object?>;
      expect(json['arc'], [
        {'position': 'abstention', 'n': 66},
        {'position': 'pour', 'n': 382},
        {'position': 'abstention', 'n': 1},
        {'position': 'pour', 'n': 121},
      ]);
      expect(WidgetDecision.tryFromJson(json)!.arc, summary.arc);
      // Arc malformé : ignoré, la décision reste lisible (arc par sens).
      final read = WidgetDecision.tryFromJson({
        ...json,
        'arc': [
          {'position': 'partage', 'n': 3},
        ],
      })!;
      expect(read.arc, isNull);
      expect(read.count, summary.count);
    },
  );
}
