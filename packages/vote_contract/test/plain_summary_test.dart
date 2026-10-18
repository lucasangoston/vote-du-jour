import 'dart:convert';

import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';

final _decision = <String, Object?>{
  'id': 'VTANR5L17V217',
  'numero': 217,
  'voteMode': 'scrutin_public',
  'type': 'ensemble',
  'status': 'confirmee',
  'result': 'rejete',
  'date': '2024-10-31',
  'officialTitle':
      "l'ensemble de la proposition de loi visant à restaurer un système de "
      'retraite plus juste (première lecture).',
  'sourceUrl': 'https://www.assemblee-nationale.fr/dyn/17/scrutins/217',
  'shortTitle': 'Restaurer un système de retraite plus juste',
};

const _summary = PlainSummary(
  title: "Retour de l'âge légal de départ à 62 ans",
  explanation:
      "Le texte prévoit d'abroger le relèvement de l'âge légal de départ à "
      'la retraite décidé en 2023.',
  points: [
    "L'âge légal de départ revient à 62 ans.",
    'La durée de cotisation revient à 42 annuités.',
    'Les pertes de recettes sont compensées par une taxe sur le tabac.',
  ],
  promptVersion: 1,
);

Object? _roundTrip(Object? json) => jsonDecode(jsonEncode(json));

void main() {
  test('sans résumé : titre court, pas d\'explication', () {
    final d = DecisionSummary.tryFromJson(_decision)!;
    expect(d.summary, isNull);
    expect(d.displayTitle, 'Restaurer un système de retraite plus juste');
    expect(d.explanation, isNull);
    expect(d.toJson().containsKey('summary'), isFalse);
  });

  test('le titre du résumé remplace le titre court', () {
    final d = DecisionSummary.tryFromJson(_decision)!.withSummary(_summary);
    expect(d.displayTitle, "Retour de l'âge légal de départ à 62 ans");
    expect(d.explanation, startsWith("Le texte prévoit d'abroger"));
  });

  test('l\'index publie le titre et la phrase, sans les points', () {
    final index = DecisionIndex(
      generatedAt: DateTime.utc(2026, 10, 18),
      decisions: [
        DecisionSummary.tryFromJson(_decision)!.withSummary(_summary),
      ],
    );
    final json = _roundTrip(index.toJson()) as Map<String, Object?>;
    final published = (json['decisions'] as List).single as Map;
    expect(published['summary'], {
      'title': "Retour de l'âge légal de départ à 62 ans",
      'explanation': _summary.explanation,
      'promptVersion': 1,
    });
    final again = DecisionIndex.fromJson(json).decisions.single;
    expect(again.summary!.title, _summary.title);
    expect(again.summary!.points, isEmpty);
  });

  test('le fichier de détail publie aussi les points', () {
    final detail = DecisionDetail(
      decision: DecisionSummary.tryFromJson(_decision)!.withSummary(_summary),
    );
    final json = _roundTrip(detail.toJson()) as Map<String, Object?>;
    final summary = (json['decision'] as Map)['summary'] as Map;
    expect(summary['points'], _summary.points);
    expect(DecisionDetail.fromJson(json).decision.summary, _summary);
  });

  test('un résumé malformé est ignoré, la décision reste lisible', () {
    for (final bad in [
      'texte',
      {'title': '', 'explanation': 'x', 'promptVersion': 1},
      {'title': 'x', 'explanation': 'x'},
      {'title': 'x', 'explanation': 3, 'promptVersion': 1},
    ]) {
      final d = DecisionSummary.tryFromJson({..._decision, 'summary': bad});
      expect(d, isNotNull, reason: '$bad');
      expect(d!.summary, isNull, reason: '$bad');
    }
  });

  test('un point illisible est ignoré', () {
    final s = PlainSummary.tryFromJson({
      'title': 't',
      'explanation': 'e',
      'promptVersion': 2,
      'points': ['a', 3, '', 'b'],
    })!;
    expect(s.points, ['a', 'b']);
    expect(s.promptVersion, 2);
  });
}
