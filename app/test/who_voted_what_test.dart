import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:votedujour/src/decision_detail/group_logo.dart';
import 'package:votedujour/src/decision_detail/group_ranking.dart';
import 'package:votedujour/src/decision_detail/who_voted_what.dart';
import 'package:votedujour/src/theme.dart';

GroupVoteDetail _group(
  String abbreviation,
  GroupPosition position, {
  int pour = 0,
  int contre = 0,
  int abstentions = 0,
  int nonVotants = 0,
  String? name,
}) => GroupVoteDetail(
  organeRef: 'PO$abbreviation',
  name: name ?? 'Groupe $abbreviation',
  abbreviation: abbreviation,
  position: position,
  count: VoteCount(
    pour: pour,
    contre: contre,
    abstentions: abstentions,
    nonVotants: nonVotants,
  ),
);

// Scrutin 8706 (13 octobre 2026), dans l'ordre du fichier publié.
final _scrutin8706 = [
  _group('RN', GroupPosition.pour, pour: 121),
  _group('EPR', GroupPosition.pour, pour: 89, nonVotants: 1),
  _group('LFI-NFP', GroupPosition.abstention, pour: 4, abstentions: 66),
  _group('SOC', GroupPosition.pour, pour: 68),
  _group('DR', GroupPosition.pour, pour: 45),
  _group('EcoS', GroupPosition.pour, pour: 38),
  _group('Dem', GroupPosition.pour, pour: 37),
  _group('HOR', GroupPosition.pour, pour: 34),
  _group('LIOT', GroupPosition.pour, pour: 23),
  _group('UDR', GroupPosition.pour, pour: 16, abstentions: 1),
  _group('GDR', GroupPosition.pour, pour: 17),
  _group('NI', GroupPosition.pour, pour: 11, name: 'Non inscrit'),
];

List<String?> _abbreviations(GroupRow row) => [
  for (final g in row.groups) g.abbreviation,
];

void main() {
  group('rankGroups', () {
    test('scrutin 8706 : Pour, Contre vide, Abstention', () {
      final rows = rankGroups(_scrutin8706);
      expect(rows.map((r) => r.position), [
        GroupPosition.pour,
        GroupPosition.contre,
        GroupPosition.abstention,
      ]);
      // Du plus grand nombre de voix au plus petit : GDR (17) avant UDR (16).
      expect(_abbreviations(rows[0]), [
        'RN',
        'EPR',
        'SOC',
        'DR',
        'EcoS',
        'Dem',
        'HOR',
        'LIOT',
        'GDR',
        'UDR',
        'NI',
      ]);
      expect(rows[1].groups, isEmpty);
      expect(_abbreviations(rows[2]), ['LFI-NFP']);
    });

    test('chaque position a sa rangée, aucun groupe ne disparaît', () {
      final groups = [
        _group('A', GroupPosition.nonVotant),
        _group('B', GroupPosition.partage, pour: 3, contre: 3),
        _group('C', GroupPosition.contre, contre: 12),
        _group('D', GroupPosition.abstention, abstentions: 5),
        _group('E', GroupPosition.pour, pour: 7),
        _group('F', GroupPosition.contre, contre: 40, pour: 2),
        _group('G', GroupPosition.nonVotant, nonVotants: 1),
      ];
      final rows = rankGroups(groups);
      expect(rows.map((r) => r.position), [
        GroupPosition.pour,
        GroupPosition.contre,
        GroupPosition.abstention,
        GroupPosition.partage,
        GroupPosition.nonVotant,
      ]);
      expect(_abbreviations(rows[0]), ['E']);
      expect(_abbreviations(rows[1]), ['F', 'C']);
      expect(_abbreviations(rows[2]), ['D']);
      expect(_abbreviations(rows[3]), ['B']);
      // À égalité (aucune voix), l'ordre du fichier est gardé.
      expect(_abbreviations(rows[4]), ['A', 'G']);
      expect(rows.expand((r) => r.groups), hasLength(groups.length));
    });

    test('rangées vides : Pour, Contre et Abstention restent', () {
      final rows = rankGroups([
        _group('A', GroupPosition.nonVotant),
        _group('B', GroupPosition.pour, pour: 1),
      ]);
      expect(rows.map((r) => (r.position, r.groups.length)), [
        (GroupPosition.pour, 1),
        (GroupPosition.contre, 0),
        (GroupPosition.abstention, 0),
        (GroupPosition.nonVotant, 1),
      ]);
      expect(rankGroups(const []).map((r) => r.position), [
        GroupPosition.pour,
        GroupPosition.contre,
        GroupPosition.abstention,
      ]);
    });
  });

  group('groupFigure', () {
    test('voix de la position seules', () {
      expect(groupFigure(_group('RN', GroupPosition.pour, pour: 121)), '121');
      expect(groupFigure(_group('X', GroupPosition.contre, contre: 30)), '30');
      expect(
        groupFigure(_group('X', GroupPosition.abstention, abstentions: 8)),
        '8',
      );
      // Les non-votants ne comptent pas comme des voix.
      expect(
        groupFigure(_group('EPR', GroupPosition.pour, pour: 89, nonVotants: 1)),
        '89',
      );
    });

    test('groupe divisé : voix de la position, puis les autres', () {
      expect(
        groupFigure(
          _group('LFI-NFP', GroupPosition.abstention, pour: 4, abstentions: 66),
        ),
        '66 · 4 pour',
      );
      expect(
        groupFigure(
          _group('UDR', GroupPosition.pour, pour: 16, abstentions: 1),
        ),
        '16 · 1 abst.',
      );
      expect(
        groupFigure(
          _group(
            'X',
            GroupPosition.contre,
            pour: 2,
            contre: 30,
            abstentions: 1,
          ),
        ),
        '30 · 2 pour · 1 abst.',
      );
    });

    test('groupe partagé et groupe qui n\'a pas voté', () {
      expect(
        groupFigure(_group('X', GroupPosition.partage, pour: 3, contre: 3)),
        '3 pour · 3 contre',
      );
      expect(
        groupFigure(_group('X', GroupPosition.nonVotant, nonVotants: 1)),
        isNull,
      );
    });
  });

  test('logos par sigle, vignette à sigle sinon', () {
    expect(groupLogoAsset(_scrutin8706.first), 'assets/group_logos/rn.png');
    final ni = _scrutin8706.last;
    expect(groupLogoAsset(ni), isNull);
    expect(groupMark(ni), 'NI');
    expect(groupCaption(ni), 'Non inscrits');
    const unknown = GroupVoteDetail(
      organeRef: 'PO999999',
      name: 'Nouveau groupe des territoires',
      position: GroupPosition.pour,
      count: VoteCount(pour: 15, contre: 0, abstentions: 0, nonVotants: 0),
    );
    expect(groupLogoAsset(unknown), isNull);
    expect(groupMark(unknown), 'NGD');
    expect(groupCaption(unknown), 'Nouveau groupe des territoires');
  });

  for (final brightness in Brightness.values) {
    testWidgets('section du scrutin 8706 (${brightness.name})', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(brightness),
          home: Scaffold(
            body: SingleChildScrollView(child: WhoVotedWhat(_scrutin8706)),
          ),
        ),
      );
      expect(find.text('Pour'), findsOneWidget);
      expect(find.text('Contre'), findsOneWidget);
      expect(find.text('Abstention'), findsOneWidget);
      expect(find.text('Partagé'), findsNothing);
      expect(find.text("N'ont pas voté"), findsNothing);
      expect(find.text('Aucun groupe'), findsOneWidget);
      expect(find.byType(GroupTile), findsNWidgets(12));
      expect(find.byType(Image), findsNWidgets(11));
      expect(find.text('121'), findsOneWidget);
      expect(find.text('66 · 4 pour'), findsOneWidget);
      expect(find.text('16 · 1 abst.'), findsOneWidget);
      expect(find.text('NI'), findsOneWidget);
      expect(find.text('Non inscrits'), findsOneWidget);
      expect(
        find.text(
          'Groupes classés selon la position de la majorité de leurs '
          'membres.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp('^Groupe LFI-NFP : Abstention, 4 pour, 0 contre'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('motion de censure : les groupes non votants ont leur rangée', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WhoVotedWhat([
              _group('RN', GroupPosition.nonVotant),
              _group('EPR', GroupPosition.nonVotant, nonVotants: 1),
              _group('LFI-NFP', GroupPosition.pour, pour: 71),
              _group('SOC', GroupPosition.pour, pour: 20),
              _group('NI', GroupPosition.nonVotant),
            ]),
          ),
        ),
      ),
    );
    expect(find.text("N'ont pas voté"), findsOneWidget);
    expect(find.text('Aucun groupe'), findsNWidgets(2));
    expect(find.byType(GroupTile), findsNWidgets(5));
    expect(find.text('71'), findsOneWidget);
    expect(find.text('RN'), findsOneWidget);
  });
}
