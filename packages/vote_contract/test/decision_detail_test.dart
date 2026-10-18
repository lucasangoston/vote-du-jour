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
