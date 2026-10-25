import 'dart:convert';

import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';

/// Texte en débat le lundi 19 octobre 2026 au soir (scrutins réels du PLF
/// 2027), tel que le publie le job.
final _inDebate = <String, Object?>{
  'dossierRef': 'DLR5L17N54629',
  'shortTitle': 'Projet de loi de finances pour 2027 (première partie)',
  'dossierUrl':
      'https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N54629',
  'seanceRef': 'RUANR5L17S2027IDS30951',
  'startsAt': '2026-10-19T19:30:00.000Z',
  'articles': [
    {
      'number': '40',
      'outcome': 'rejete',
      'date': '2026-10-19',
      'scrutinRef': 'VTANR5L17V8892',
    },
    {
      'number': '39',
      'outcome': 'supprime',
      'date': '2026-10-19',
      'scrutinRef': 'VTANR5L17V8889',
    },
    {
      'number': '38',
      'outcome': 'adopte',
      'date': '2026-10-19',
      'scrutinRef': 'VTANR5L17V8888',
    },
    {
      'number': '3 bis A',
      'outcome': 'adopte',
      'date': '2026-10-15',
      'scrutinRef': 'VTANR5L17V8737',
    },
  ],
};

/// Résumé du texte en débat, rédigé par le job (#73).
final _summary = <String, Object?>{
  'title': 'Financement de la Sécurité sociale en 2027',
  'explanation':
      'Le texte fixe les recettes et les dépenses de la Sécurité '
      'sociale pour 2027.',
  'points': ['Point un.', 'Point deux.', 'Point trois.'],
  'promptVersion': 1,
};

final _decision = <String, Object?>{
  'id': 'VTANR5L17V8706',
  'numero': 8706,
  'voteMode': 'scrutin_public',
  'type': 'ensemble',
  'status': 'confirmee',
  'result': 'adopte',
  'date': '2026-10-13',
  'officialTitle': "l'ensemble de la proposition de loi organique (…).",
  'sourceUrl': 'https://www.assemblee-nationale.fr/dyn/17/scrutins/8706',
};

Map<String, Object?> _index({Object? inDebate = _absent}) => {
  'schemaVersion': 1,
  'generatedAt': '2026-10-19T21:00:00.000Z',
  'decisions': [_decision],
  if (!identical(inDebate, _absent)) 'inDebate': inDebate,
};

const _absent = Object();

Object? _roundTrip(Object? json) => jsonDecode(jsonEncode(json));

void main() {
  group('InDebate', () {
    test('aller-retour', () {
      final d = InDebate.tryFromJson(_inDebate)!;
      expect(d.dossierRef, 'DLR5L17N54629');
      expect(d.startsAt, DateTime.utc(2026, 10, 19, 19, 30));
      expect(d.startsAt.isUtc, isTrue);
      expect(d.articles.map((a) => (a.number, a.outcome)), [
        ('40', ArticleOutcome.rejete),
        ('39', ArticleOutcome.supprime),
        ('38', ArticleOutcome.adopte),
        ('3 bis A', ArticleOutcome.adopte),
      ]);
      expect(d.articles.first.date, DateTime.utc(2026, 10, 19));
      expect(d.articles.first.scrutinNumero, 8892);
      expect(_roundTrip(d.toJson()), _inDebate);
    });

    test('résumé du texte (#73) : optionnel, points compris', () {
      expect(InDebate.tryFromJson(_inDebate)!.summary, isNull);
      expect(
        (_roundTrip(InDebate.tryFromJson(_inDebate)!.toJson()) as Map)
            .containsKey('summary'),
        isFalse,
      );
      final json = {..._inDebate, 'summary': _summary};
      final d = InDebate.tryFromJson(json)!;
      expect(d.summary!.title, 'Financement de la Sécurité sociale en 2027');
      expect(d.summary!.points, hasLength(3));
      // Pas de fichier de détail pour le texte en débat : les points sont
      // publiés dans l'index.
      expect(_roundTrip(d.toJson()), json);
    });

    test('résumé malformé : ignoré, le bloc reste lisible', () {
      final d = InDebate.tryFromJson({
        ..._inDebate,
        'summary': {'title': 'Sans explication'},
      })!;
      expect(d.summary, isNull);
      expect(d.articles, hasLength(4));
    });

    test('withSummary garde le reste', () {
      final d = InDebate.tryFromJson(_inDebate)!;
      final summary = PlainSummary.tryFromJson(_summary)!;
      final s = d.withSummary(summary);
      expect(s.summary, same(summary));
      expect(_roundTrip(s.withSummary(null).toJson()), _inDebate);
      expect(s.articles, same(d.articles));
    });

    test('sans article voté : liste vide', () {
      final d = InDebate.tryFromJson({..._inDebate, 'articles': []})!;
      expect(d.articles, isEmpty);
      expect((_roundTrip(d.toJson()) as Map)['articles'], isEmpty);
      expect(
        InDebate.tryFromJson({..._inDebate}..remove('articles'))!.articles,
        isEmpty,
      );
    });

    test('article de sort inconnu (job plus récent) ou malformé : ignoré', () {
      final d = InDebate.tryFromJson({
        ..._inDebate,
        'articles': [
          {
            'number': '41',
            'outcome': 'reserve',
            'date': '2026-10-19',
            'scrutinRef': 'VTANR5L17V8900',
          },
          {'number': '42', 'outcome': 'adopte'},
          'x',
          (_inDebate['articles'] as List).first,
        ],
      })!;
      expect(d.articles.map((a) => a.number), ['40']);
    });

    test('champ manquant : illisible', () {
      for (final key in [
        'dossierRef',
        'shortTitle',
        'dossierUrl',
        'seanceRef',
        'startsAt',
      ]) {
        expect(InDebate.tryFromJson({..._inDebate}..remove(key)), isNull);
      }
      expect(InDebate.tryFromJson({..._inDebate, 'shortTitle': ' '}), isNull);
      expect(InDebate.tryFromJson('x'), isNull);
    });
  });

  group('inDebate dans l\'index', () {
    test('absent (index antérieur au ticket #55, ou rien en débat) : null', () {
      final index = DecisionIndex.fromJson(_index());
      expect(index.inDebate, isNull);
      expect(index.toJson().containsKey('inDebate'), isFalse);
    });

    test('aller-retour', () {
      final index = DecisionIndex.fromJson(_index(inDebate: _inDebate));
      expect(index.inDebate!.shortTitle, _inDebate['shortTitle']);
      expect((_roundTrip(index.toJson()) as Map)['inDebate'], _inDebate);
    });

    test('malformé : ignoré, les décisions restent lisibles', () {
      final index = DecisionIndex.fromJson(_index(inDebate: 'PLF'));
      expect(index.inDebate, isNull);
      expect(index.decisions.single.id, 'VTANR5L17V8706');
    });

    test('ajout rétrocompatible : même version de schéma', () {
      final published =
          _roundTrip(
                DecisionIndex.fromJson(_index(inDebate: _inDebate)).toJson(),
              )
              as Map<String, Object?>;
      expect(published['schemaVersion'], schemaVersion);
      // Une app antérieure ignore le champ.
      expect(
        DecisionIndex.fromJson({...published}..remove('inDebate')).decisions,
        hasLength(1),
      );
    });

    test('withInDebate, withUpcoming et withDecisions gardent le reste', () {
      final index = DecisionIndex.fromJson(_index());
      final d = InDebate.tryFromJson(_inDebate)!;
      final updated = index.withInDebate(d);
      expect(updated.decisions, same(index.decisions));
      expect(updated.generatedAt, index.generatedAt);
      expect(updated.inDebate, same(d));
      expect(updated.withUpcoming(const []).inDebate, same(d));
      final later = DateTime.utc(2026, 10, 20);
      final redone = updated.withDecisions(const [], generatedAt: later);
      expect(redone.inDebate, same(d));
      expect(redone.generatedAt, later);
      expect(redone.decisions, isEmpty);
    });
  });
}
