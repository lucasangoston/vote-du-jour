import 'dart:convert';

import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';

void main() {
  final decision = DecisionSummary(
    id: 'VTANR5L17V8706',
    numero: 8706,
    type: DecisionType.ensembleTexte,
    status: DecisionStatus.confirmee,
    result: VoteResult.adopte,
    date: DateTime.utc(2026, 10, 13),
    officialTitle: 'la proposition de loi organique exemple.',
    sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/8706',
  );
  final arguments = DecisionArguments(
    pour: const [
      GroupArgument(
        group: 'SOC',
        organeRef: 'PO845419',
        text: 'Le texte renforce la protection des victimes.',
      ),
    ],
    abstention: const [
      GroupArgument(group: 'LFI-NFP', text: 'Le texte manque de moyens.'),
    ],
    source: ArgumentsSource(
      date: DateTime.utc(2026, 10, 13),
      url:
          'https://www.assemblee-nationale.fr/dyn/17/comptes-rendus/seance/'
          'CRSANR5L17S2027O1N020',
    ),
    promptVersion: 1,
  );

  DecisionDetail roundTrip(DecisionDetail d) =>
      DecisionDetail.fromJson(jsonDecode(jsonEncode(d.toJson())));

  test('format publié', () {
    expect(arguments.toJson(), {
      'pour': [
        {
          'group': 'SOC',
          'organeRef': 'PO845419',
          'text': 'Le texte renforce la protection des victimes.',
        },
      ],
      'contre': <Object?>[],
      'abstention': [
        {'group': 'LFI-NFP', 'text': 'Le texte manque de moyens.'},
      ],
      'source': {
        'date': '2026-10-13',
        'url':
            'https://www.assemblee-nationale.fr/dyn/17/comptes-rendus/seance/'
            'CRSANR5L17S2027O1N020',
      },
      'promptVersion': 1,
    });
  });

  test('aller-retour dans le fichier de détail', () {
    final detail = DecisionDetail(decision: decision, arguments: arguments);
    final reread = roundTrip(detail);
    expect(reread.arguments, arguments);
    expect(jsonEncode(reread.toJson()), jsonEncode(detail.toJson()));
    // withDecision garde les arguments (résumé appliqué après coup).
    expect(reread.withDecision(decision).arguments, arguments);
    expect(reread.withArguments(null).arguments, isNull);
  });

  test('champ absent : pas de clé arguments (rétrocompatible)', () {
    final detail = DecisionDetail(decision: decision);
    expect(detail.toJson().containsKey('arguments'), isFalse);
    expect(roundTrip(detail).arguments, isNull);
  });

  test('arguments malformés ignorés, le détail reste lisible', () {
    Map<String, Object?> withArguments(Object? value) => {
      ...DecisionDetail(decision: decision).toJson(),
      'arguments': value,
    };
    for (final bad in [
      'texte',
      {'pour': <Object?>[], 'source': arguments.source.toJson()},
      {
        'pour': [
          {'group': 'SOC', 'text': 'Un argument.'},
        ],
        'promptVersion': 1,
      },
      {
        'pour': [
          {'group': '', 'text': 'Sans groupe.'},
        ],
        'source': arguments.source.toJson(),
        'promptVersion': 1,
      },
    ]) {
      final detail = DecisionDetail.fromJson(
        jsonDecode(jsonEncode(withArguments(bad))),
      );
      expect(detail.arguments, isNull, reason: '$bad');
      expect(detail.decision.id, 'VTANR5L17V8706');
    }
  });

  test('un argument illisible est ignoré, les autres gardés', () {
    final json = arguments.toJson()
      ..['contre'] = [
        {'group': 'RN'},
        {'group': 'RN', 'text': 'Un argument lisible.'},
      ];
    final reread = DecisionArguments.tryFromJson(jsonDecode(jsonEncode(json)));
    expect(reread!.contre, const [
      GroupArgument(group: 'RN', text: 'Un argument lisible.'),
    ]);
  });
}
