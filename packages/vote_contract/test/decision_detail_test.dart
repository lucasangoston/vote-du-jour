import 'dart:convert';

import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';

void main() {
  final scrutin = DecisionSummary(
    id: 'VTANR5L17V6346',
    numero: 6346,
    type: DecisionType.ensembleTexte,
    status: DecisionStatus.confirmee,
    result: VoteResult.adopte,
    date: DateTime.utc(2026, 4, 9),
    officialTitle: "l'ensemble du projet de loi exemple.",
    sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/6346',
    shortTitle: 'Exemple',
    stage: 'Texte de compromis (CMP)',
  );

  DecisionDetail roundTrip(DecisionDetail d) =>
      DecisionDetail.fromJson(jsonDecode(jsonEncode(d.toJson())));

  test('chemin du fichier de détail', () {
    expect(
      decisionDetailPath('VTANR5L17V6346'),
      'v1/decisions/VTANR5L17V6346.json',
    );
    expect(
      decisionDetailPath('L17-VD234087DEC'),
      'v1/decisions/L17-VD234087DEC.json',
    );
  });

  test('aller-retour d\'un scrutin public', () {
    final detail = DecisionDetail(
      decision: scrutin,
      count: const VoteCount(
        pour: 141,
        contre: 0,
        abstentions: 12,
        nonVotants: 2,
      ),
      groups: const [
        GroupVoteDetail(
          organeRef: 'PO845425',
          name: 'Droite Républicaine',
          abbreviation: 'DR',
          position: GroupPosition.abstention,
          count: VoteCount(pour: 5, contre: 0, abstentions: 6, nonVotants: 0),
        ),
        GroupVoteDetail(
          organeRef: 'PO0',
          name: 'Groupe non identifié',
          position: GroupPosition.nonVotant,
          count: VoteCount(pour: 0, contre: 0, abstentions: 0, nonVotants: 0),
        ),
      ],
    );
    final reread = roundTrip(detail);
    expect(jsonEncode(reread.toJson()), jsonEncode(detail.toJson()));
    expect(reread.count?.votants, 153);
    expect(reread.groups.last.abbreviation, isNull);
  });

  test('aller-retour d\'un texte adopté à main levée', () {
    final detail = DecisionDetail(
      decision: DecisionSummary(
        id: 'L17-VD234087DEC',
        voteMode: VoteMode.mainLevee,
        type: DecisionType.ensembleTexte,
        status: DecisionStatus.confirmee,
        result: VoteResult.adopte,
        date: DateTime.utc(2026, 10, 7),
        officialTitle: 'projet de loi exemple',
        sourceUrl:
            'https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N54379',
      ),
    );
    final json = detail.toJson();
    expect(json.containsKey('count'), isFalse);
    expect(json['groups'], isEmpty);
    final reread = roundTrip(detail);
    expect(reread.decision.voteMode, VoteMode.mainLevee);
    expect(reread.decision.numero, isNull);
    expect(reread.count, isNull);
    expect(reread.groups, isEmpty);
  });

  test('ignore les champs et positions inconnus', () {
    final json = DecisionDetail(decision: scrutin).toJson()
      ..['futurChamp'] = true
      ..['groups'] = [
        {
          'organeRef': 'PO1',
          'name': 'Groupe A',
          'position': 'pour',
          'count': {'pour': 1, 'contre': 0, 'abstentions': 0, 'nonVotants': 0},
        },
        {
          'organeRef': 'PO2',
          'name': 'Groupe B',
          'position': 'inconnue',
          'count': {'pour': 1, 'contre': 0, 'abstentions': 0, 'nonVotants': 0},
        },
      ];
    final detail = DecisionDetail.fromJson(jsonDecode(jsonEncode(json)));
    expect(detail.groups.map((g) => g.name), ['Groupe A']);
  });

  test('refuse une autre version ou une décision illisible', () {
    expect(
      () => DecisionDetail.fromJson({'schemaVersion': 2}),
      throwsA(isA<UnsupportedSchemaException>()),
    );
    expect(
      () => DecisionDetail.fromJson({'schemaVersion': 1, 'decision': {}}),
      throwsFormatException,
    );
  });

  group('sièges du scrutin (#71)', () {
    const seats = [
      HemicycleSeat(place: 1, group: 'PO845401', vote: SeatVote.pour),
      HemicycleSeat(place: 2, group: 'PO845401', vote: SeatVote.contre),
      HemicycleSeat(place: 410, group: 'PO845419', vote: SeatVote.abstention),
      HemicycleSeat(place: 595, group: 'PO845413', vote: SeatVote.nonVotant),
      HemicycleSeat(place: 650, group: 'PO845413', vote: SeatVote.absent),
    ];
    final detail = DecisionDetail(
      decision: scrutin,
      groups: const [
        GroupVoteDetail(
          organeRef: 'PO845401',
          name: 'Rassemblement National',
          abbreviation: 'RN',
          color: '#313567',
          position: GroupPosition.pour,
          count: VoteCount(pour: 1, contre: 1, abstentions: 0, nonVotants: 0),
        ),
      ],
      seats: seats,
    );

    test('tableau compact [place, groupe, vote]', () {
      final json = jsonDecode(jsonEncode(detail.toJson())) as Map;
      expect(json['seats'], [
        [1, 'PO845401', 'p'],
        [2, 'PO845401', 'c'],
        [410, 'PO845419', 'a'],
        [595, 'PO845413', 'n'],
        [650, 'PO845413', 'x'],
      ]);
      expect((json['groups'] as List).single['color'], '#313567');
    });

    test('aller-retour', () {
      final reread = roundTrip(detail);
      expect(reread.seats, seats);
      expect(reread.groups.single.color, '#313567');
      expect(jsonEncode(reread.toJson()), jsonEncode(detail.toJson()));
    });

    test('ancien détail sans sièges ni couleurs : toujours lisible', () {
      final json =
          jsonDecode(jsonEncode(detail.toJson())) as Map<String, Object?>
            ..remove('seats');
      ((json['groups'] as List).single as Map).remove('color');
      final reread = DecisionDetail.fromJson(json);
      expect(reread.seats, isNull);
      expect(reread.groups.single.color, isNull);
      expect(reread.groups.single.abbreviation, 'RN');
      expect(reread.toJson().containsKey('seats'), isFalse);
    });

    test('sans sièges, le champ est absent du fichier', () {
      expect(
        DecisionDetail(decision: scrutin).toJson().containsKey('seats'),
        isFalse,
      );
    });

    test('couleur malformée : ignorée, le groupe reste lisible', () {
      for (final color in ['bleu', '#31356', 'FF0000', 42]) {
        final json = detail.toJson();
        final groups = jsonDecode(jsonEncode(json['groups'])) as List;
        (groups.single as Map)['color'] = color;
        json['groups'] = groups;
        final reread = DecisionDetail.fromJson(jsonDecode(jsonEncode(json)));
        expect(reread.groups.single.color, isNull, reason: '$color');
        expect(reread.groups.single.name, 'Rassemblement National');
      }
    });

    test('un siège illisible rend tous les sièges illisibles', () {
      for (final bad in [
        [3, 'PO845401', 'z'], // vote inconnu
        [3, 'PO845401'], // vote manquant
        ['3', 'PO845401', 'p'], // place en texte
        [0, 'PO845401', 'p'], // place nulle
        [3, '', 'p'], // groupe vide
        [1, 'PO845401', 'p'], // place en double
        {'place': 3}, // objet au lieu d'un tableau
      ]) {
        final json =
            jsonDecode(jsonEncode(detail.toJson())) as Map<String, Object?>;
        (json['seats'] as List).add(bad);
        final reread = DecisionDetail.fromJson(json);
        expect(reread.seats, isNull, reason: '$bad');
        expect(reread.groups, hasLength(1));
      }
      expect(HemicycleSeat.tryParseList([]), isNull);
      expect(HemicycleSeat.tryParseList('p'), isNull);
    });
  });

  test('position d\'un groupe calculée sur son décompte', () {
    GroupPosition of(int pour, int contre, int abst) => GroupPosition.fromCount(
      VoteCount(pour: pour, contre: contre, abstentions: abst, nonVotants: 3),
    );
    expect(of(5, 1, 0), GroupPosition.pour);
    expect(of(0, 7, 66), GroupPosition.abstention);
    expect(of(2, 16, 0), GroupPosition.contre);
    expect(of(4, 4, 1), GroupPosition.partage);
    expect(of(0, 0, 0), GroupPosition.nonVotant);
  });
}
