import 'dart:convert';

import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';

/// Vote solennel inscrit à l'ordre du jour du 27 octobre 2026 (agenda réel
/// du 21/10/2026, séance RUANR5L17S2027IDS30964), tel que le publie le job.
final _vote = <String, Object?>{
  'id': 'RUANR5L17S2027IDS30964PT53289',
  'kind': 'vote_solennel',
  'startsAt': '2026-10-27T14:00:00.000Z',
  'seanceRef': 'RUANR5L17S2027IDS30964',
  'label':
      'Vote solennel sur le projet de loi de financement de la sécurité '
      'sociale pour 2027',
  'shortTitle': 'Projet de loi de financement de la sécurité sociale pour 2027',
  'dossierRef': 'DLR5L17N54951',
  'dossierUrl':
      'https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N54951',
};

/// Suite de la discussion du même texte, la veille au soir.
final _discussion = <String, Object?>{
  'id': 'RUANR5L17S2027IDS30963PT53280',
  'kind': 'discussion',
  'startsAt': '2026-10-26T20:30:00.000Z',
  'seanceRef': 'RUANR5L17S2027IDS30963',
  'label':
      'Suite de la discussion du projet de loi de financement de la '
      'sécurité sociale pour 2027',
  'shortTitle': 'Projet de loi de financement de la sécurité sociale pour 2027',
  'inProgress': true,
  'dossierRef': 'DLR5L17N54951',
  'dossierUrl':
      'https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N54951',
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

Map<String, Object?> _index({Object? upcoming = _absent}) => {
  'schemaVersion': 1,
  'generatedAt': '2026-10-21T17:17:00.000Z',
  'decisions': [_decision],
  if (!identical(upcoming, _absent)) 'upcoming': upcoming,
};

const _absent = Object();

Object? _roundTrip(Object? json) => jsonDecode(jsonEncode(json));

void main() {
  group('UpcomingItem', () {
    test('aller-retour d\'un vote solennel', () {
      final item = UpcomingItem.tryFromJson(_vote)!;
      expect(item.kind, UpcomingKind.voteSolennel);
      expect(item.startsAt, DateTime.utc(2026, 10, 27, 14));
      expect(item.startsAt.isUtc, isTrue);
      expect(item.inProgress, isFalse);
      expect(_roundTrip(item.toJson()), _vote);
    });

    test('aller-retour d\'une discussion en cours', () {
      final item = UpcomingItem.tryFromJson(_discussion)!;
      expect(item.kind, UpcomingKind.discussion);
      expect(item.inProgress, isTrue);
      expect(_roundTrip(item.toJson()), _discussion);
    });

    test('l\'heure est écrite en UTC, même lue avec un décalage', () {
      final item = UpcomingItem.tryFromJson({
        ..._vote,
        'startsAt': '2026-10-27T15:00:00.000+01:00',
      })!;
      expect(item.toJson()['startsAt'], '2026-10-27T14:00:00.000Z');
    });

    test('sans dossier : champs omis', () {
      final json = {..._vote}
        ..remove('dossierRef')
        ..remove('dossierUrl');
      final item = UpcomingItem.tryFromJson(json)!;
      expect(item.dossierRef, isNull);
      expect(_roundTrip(item.toJson()), json);
    });

    test('nature inconnue (job plus récent) ou champ manquant : illisible', () {
      expect(UpcomingItem.tryFromJson({..._vote, 'kind': 'qag'}), isNull);
      for (final key in ['id', 'startsAt', 'seanceRef', 'label']) {
        expect(UpcomingItem.tryFromJson({..._vote}..remove(key)), isNull);
      }
      expect(UpcomingItem.tryFromJson({..._vote, 'shortTitle': ' '}), isNull);
      expect(
        UpcomingItem.tryFromJson({..._vote, 'startsAt': 'demain'}),
        isNull,
      );
    });
  });

  group('upcoming dans l\'index', () {
    test('absent (index antérieur au ticket #52) : null', () {
      final index = DecisionIndex.fromJson(_index());
      expect(index.upcoming, isNull);
      expect(index.toJson().containsKey('upcoming'), isFalse);
    });

    test('liste vide : rien d\'inscrit, gardée telle quelle', () {
      final index = DecisionIndex.fromJson(_index(upcoming: []));
      expect(index.upcoming, isEmpty);
      expect((_roundTrip(index.toJson()) as Map)['upcoming'], isEmpty);
    });

    test('aller-retour, points illisibles ignorés', () {
      final index = DecisionIndex.fromJson(
        _index(
          upcoming: [
            _discussion,
            {..._vote, 'kind': 'qag'},
            'x',
            _vote,
          ],
        ),
      );
      expect(index.upcoming!.map((u) => u.id), [
        _discussion['id'],
        _vote['id'],
      ]);
      expect((_roundTrip(index.toJson()) as Map)['upcoming'], [
        _discussion,
        _vote,
      ]);
    });

    test('un champ de type inattendu n\'empêche pas de lire les décisions', () {
      final index = DecisionIndex.fromJson(_index(upcoming: 'demain'));
      expect(index.upcoming, isNull);
      expect(index.decisions.single.id, 'VTANR5L17V8706');
    });

    test('ajout rétrocompatible : même version de schéma, les décisions '
        'restent lisibles par une app antérieure', () {
      final published =
          _roundTrip(DecisionIndex.fromJson(_index(upcoming: [_vote])).toJson())
              as Map<String, Object?>;
      expect(published['schemaVersion'], 1);
      expect(schemaVersion, 1);
      // Une app antérieure lit `schemaVersion`, `generatedAt` et
      // `decisions`, et ignore les autres champs.
      expect(
        DecisionIndex.fromJson({...published}..remove('upcoming')).decisions,
        hasLength(1),
      );
      expect(
        (published['decisions'] as List).single,
        DecisionSummary.tryFromJson(_decision)!.toJson(),
      );
    });

    test('withUpcoming garde les décisions', () {
      final index = DecisionIndex.fromJson(_index());
      final item = UpcomingItem.tryFromJson(_vote)!;
      final updated = index.withUpcoming([item]);
      expect(updated.decisions, same(index.decisions));
      expect(updated.generatedAt, index.generatedAt);
      expect(updated.upcoming, [item]);
    });
  });
}
