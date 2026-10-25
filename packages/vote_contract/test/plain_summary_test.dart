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

  group('titre court (widgets, liste)', () {
    const court = PlainSummary(
      title: "Retour de l'âge légal de départ à 62 ans",
      shortTitle: 'Retraite à 62 ans',
      explanation: 'Le texte prévoit une mesure.',
      promptVersion: 2,
    );

    test('publié dans l\'index et dans le détail', () {
      final d = DecisionSummary.tryFromJson(_decision)!.withSummary(court);
      final index =
          _roundTrip(
                DecisionIndex(
                  generatedAt: DateTime.utc(2026, 10, 25),
                  decisions: [d],
                ).toJson(),
              )
              as Map<String, Object?>;
      final published = (index['decisions'] as List).single as Map;
      expect((published['summary'] as Map)['shortTitle'], 'Retraite à 62 ans');
      final again = DecisionIndex.fromJson(index).decisions.single;
      expect(again.summary!.shortTitle, 'Retraite à 62 ans');
      expect(again.compactTitle, 'Retraite à 62 ans');

      final detail =
          _roundTrip(DecisionDetail(decision: d).toJson())
              as Map<String, Object?>;
      expect(DecisionDetail.fromJson(detail).decision.summary, court);
    });

    test('absent : champ omis, repli sur le titre habituel', () {
      expect(_summary.shortTitle, isNull);
      expect(_summary.toJson().containsKey('shortTitle'), isFalse);
      final d = DecisionSummary.tryFromJson(_decision)!;
      expect(d.compactTitle, 'Restaurer un système de retraite plus juste');
      expect(d.withSummary(_summary).compactTitle, _summary.title);
    });

    test('trop long, vide ou illisible : ignoré, le résumé reste lisible', () {
      for (final bad in <Object?>['x' * (shortTitleMaxLength + 1), '  ', 3]) {
        final s = PlainSummary.tryFromJson({
          'title': 'Titre',
          'explanation': 'e',
          'promptVersion': 2,
          'shortTitle': bad,
        });
        expect(s, isNotNull, reason: '$bad');
        expect(s!.shortTitle, isNull, reason: '$bad');
      }
      final juste = PlainSummary.tryFromJson({
        'title': 'Titre',
        'explanation': 'e',
        'promptVersion': 2,
        'shortTitle': 'x' * shortTitleMaxLength,
      });
      expect(juste!.shortTitle, hasLength(shortTitleMaxLength));
    });
  });
}
