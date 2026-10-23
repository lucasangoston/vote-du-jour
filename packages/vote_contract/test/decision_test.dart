import 'dart:convert';

import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';

/// Décision publiée avant le ticket #8 : ni `voteMode`, ni titre court.
final _legacyScrutin = <String, Object?>{
  'id': 'VTANR5L17V8706',
  'numero': 8706,
  'type': 'ensemble',
  'status': 'confirmee',
  'result': 'adopte',
  'date': '2026-10-13',
  'officialTitle':
      "la proposition de loi organique visant à adapter l'autorité "
      'judiciaire à la lutte contre les violences sexuelles et '
      'intrafamiliales (première lecture).',
  'sourceUrl': 'https://www.assemblee-nationale.fr/dyn/17/scrutins/8706',
};

/// Décision à main levée telle que la publie le job depuis le ticket #8
/// (acte réel du dossier DLR5L17N54379, 7 octobre 2026).
final _mainLevee = <String, Object?>{
  'id': 'L17-VD234087DEC',
  'voteMode': 'main_levee',
  'type': 'ensemble',
  'status': 'confirmee',
  'result': 'adopte',
  'date': '2026-10-07',
  'officialTitle':
      "projet de loi autorisant l'approbation de l'accord multilatéral "
      "entre autorités compétentes portant sur l'échange des informations "
      'GloBE',
  'sourceUrl':
      'https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N54379',
  'shortTitle':
      'Projet de loi autorisant l’approbation de l’accord multilatéral '
      'entre autorités compétentes portant sur l’échange des informations '
      'GloBE',
  'stage': "1re lecture à l'AN",
  'dossierUrl':
      'https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N54379',
};

Map<String, Object?> _index(List<Map<String, Object?>> decisions) => {
  'schemaVersion': 1,
  'generatedAt': '2026-10-17T10:17:00.000Z',
  'decisions': decisions,
};

/// Copie de la lecture d'une décision avant le ticket #8 (commit 40e9985) :
/// ce que fait une version de l'app déjà installée.
DecisionSummary? _readerBefore8(Map<String, Object?> json) {
  final type = DecisionType.tryParse(json['type']);
  final status = DecisionStatus.tryParse(json['status']);
  final result = VoteResult.tryParse(json['result']);
  final id = json['id'];
  final numero = json['numero'];
  final date = DateTime.tryParse('${json['date']}T00:00:00Z');
  final title = json['officialTitle'];
  final sourceUrl = json['sourceUrl'];
  if (type == null ||
      status == null ||
      result == null ||
      id is! String ||
      numero is! int ||
      date == null ||
      title is! String ||
      sourceUrl is! String) {
    return null;
  }
  return DecisionSummary(
    id: id,
    numero: numero,
    type: type,
    status: status,
    result: result,
    date: date,
    officialTitle: title,
    sourceUrl: sourceUrl,
  );
}

Object? _roundTrip(Object? json) => jsonDecode(jsonEncode(json));

void main() {
  group('mode de vote', () {
    test('absent (index antérieur au ticket #8) : scrutin public', () {
      final d = DecisionSummary.tryFromJson(_legacyScrutin)!;
      expect(d.voteMode, VoteMode.scrutinPublic);
      expect(d.numero, 8706);
      expect(d.shortTitle, isNull);
      expect(d.stage, isNull);
    });

    test('aller-retour d\'un scrutin public', () {
      final d = DecisionSummary.tryFromJson(_legacyScrutin)!;
      final json = _roundTrip(d.toJson()) as Map<String, Object?>;
      expect(json, {..._legacyScrutin, 'voteMode': 'scrutin_public'});
      final again = DecisionSummary.tryFromJson(json)!;
      expect(again.numero, 8706);
      expect(again.voteMode, VoteMode.scrutinPublic);
    });

    test('aller-retour d\'une décision à main levée, sans numéro', () {
      final d = DecisionSummary.tryFromJson(_mainLevee)!;
      expect(d.voteMode, VoteMode.mainLevee);
      expect(d.numero, isNull);
      expect(d.id, 'L17-VD234087DEC');
      expect(d.result, VoteResult.adopte);
      expect(d.stage, "1re lecture à l'AN");
      final json = _roundTrip(d.toJson()) as Map<String, Object?>;
      expect(json, _mainLevee);
      expect(json.containsKey('numero'), isFalse);
    });

    test('un scrutin public sans numéro est illisible', () {
      expect(
        DecisionSummary.tryFromJson({..._legacyScrutin}..remove('numero')),
        isNull,
      );
      expect(
        DecisionSummary.tryFromJson({
          ..._mainLevee,
          'voteMode': 'scrutin_public',
        }),
        isNull,
      );
    });

    test('un numéro d\'un autre type est illisible', () {
      expect(
        DecisionSummary.tryFromJson({..._mainLevee, 'numero': '12'}),
        isNull,
      );
    });

    test('un mode de vote inconnu (job plus récent) est ignoré', () {
      final index = DecisionIndex.fromJson(
        _index([
          {..._mainLevee, 'voteMode': 'vote_electronique'},
          _legacyScrutin,
        ]),
      );
      expect(index.decisions.map((d) => d.id), ['VTANR5L17V8706']);
    });

    test('un index mêlant les deux modes se relit à l\'identique', () {
      final index = DecisionIndex.fromJson(
        _index([_legacyScrutin, _mainLevee]),
      );
      final again = DecisionIndex.fromJson(_roundTrip(index.toJson()));
      expect(again.decisions.map((d) => (d.id, d.numero, d.voteMode)), [
        ('VTANR5L17V8706', 8706, VoteMode.scrutinPublic),
        ('L17-VD234087DEC', null, VoteMode.mainLevee),
      ]);
    });
  });

  group('version de l\'app antérieure au ticket #8', () {
    test('ignore une décision à main levée, sans erreur', () {
      expect(_readerBefore8(_mainLevee), isNull);
    });

    test('lit toujours les scrutins publics publiés depuis', () {
      final json =
          _roundTrip(DecisionSummary.tryFromJson(_legacyScrutin)!.toJson())
              as Map<String, Object?>;
      final old = _readerBefore8(json)!;
      expect(old.id, 'VTANR5L17V8706');
      expect(old.numero, 8706);
    });

    test('lit le reste de l\'index : les décisions à main levée sont '
        'seulement absentes de sa liste', () {
      final published =
          _roundTrip(
                DecisionIndex.fromJson(
                  _index([_mainLevee, _legacyScrutin]),
                ).toJson(),
              )
              as Map<String, Object?>;
      final old = [
        for (final d in published['decisions'] as List)
          ?_readerBefore8(d as Map<String, Object?>),
      ];
      expect(old.map((d) => d.id), ['VTANR5L17V8706']);
    });
  });

  group('statut (#10)', () {
    test('absent : confirmée', () {
      final json = {..._legacyScrutin}..remove('status');
      expect(
        DecisionSummary.tryFromJson(json)!.status,
        DecisionStatus.confirmee,
      );
    });

    test('aller-retour d\'une décision provisoire', () {
      final json = {..._legacyScrutin, 'status': 'provisoire'};
      final d = DecisionSummary.tryFromJson(json)!;
      expect(d.status, DecisionStatus.provisoire);
      final again = DecisionSummary.tryFromJson(
        _roundTrip(d.toJson()) as Map<String, Object?>,
      )!;
      expect(again.status, DecisionStatus.provisoire);
      expect(again.toJson(), d.toJson());
    });

    test('toujours écrit, même confirmée (lecteurs antérieurs à #10)', () {
      final d = DecisionSummary.tryFromJson(
        {..._legacyScrutin}..remove('status'),
      )!;
      expect(d.toJson()['status'], 'confirmee');
      expect(_readerBefore8(d.toJson()), isNotNull);
    });

    test('un statut inconnu (job plus récent) rend la décision illisible', () {
      expect(
        DecisionSummary.tryFromJson({..._legacyScrutin, 'status': 'annulee'}),
        isNull,
      );
    });

    test(
      'un index mêlant provisoires et confirmées se relit à l\'identique',
      () {
        final index = DecisionIndex.fromJson(
          _index([
            {..._legacyScrutin, 'status': 'provisoire'},
            _mainLevee,
          ]),
        );
        final again = DecisionIndex.fromJson(_roundTrip(index.toJson()));
        expect(again.decisions.map((d) => d.status), [
          DecisionStatus.provisoire,
          DecisionStatus.confirmee,
        ]);
      },
    );
  });

  group('décompte dans l\'index (#29)', () {
    const count = {'pour': 503, 'contre': 0, 'abstentions': 67};

    test('absent (index antérieur) : pas de décompte', () {
      expect(DecisionSummary.tryFromJson(_legacyScrutin)!.count, isNull);
      expect(
        DecisionSummary.tryFromJson(_legacyScrutin)!.toJson(),
        isNot(contains('count')),
      );
    });

    test('aller-retour d\'un scrutin public avec décompte', () {
      final d = DecisionSummary.tryFromJson({
        ..._legacyScrutin,
        'count': count,
      })!;
      expect(d.count, const VoteTally(pour: 503, contre: 0, abstentions: 67));
      final json = _roundTrip(d.toJson()) as Map<String, Object?>;
      expect(json['count'], count);
      expect(DecisionSummary.tryFromJson(json)!.count, d.count);
    });

    test('un décompte malformé est ignoré, la décision reste lisible', () {
      final d = DecisionSummary.tryFromJson({
        ..._legacyScrutin,
        'count': {'pour': '503'},
      })!;
      expect(d.count, isNull);
      expect(
        DecisionSummary.tryFromJson({
          ..._legacyScrutin,
          'count': {'pour': -1, 'contre': 0, 'abstentions': 0},
        })!.count,
        isNull,
      );
    });

    test('conservé par withSummary, remplacé par withCount', () {
      final d = DecisionSummary.tryFromJson({
        ..._legacyScrutin,
        'count': count,
      })!;
      expect(d.withSummary(null).count, d.count);
      expect(d.withCount(null).count, isNull);
    });

    test('VoteCount.tally : sans les non-votants', () {
      const full = VoteCount(
        pour: 503,
        contre: 0,
        abstentions: 67,
        nonVotants: 2,
      );
      expect(
        full.tally,
        const VoteTally(pour: 503, contre: 0, abstentions: 67),
      );
      expect(full.tally.total, 570);
    });

    test('lu sans erreur par une app antérieure', () {
      final json = DecisionSummary.tryFromJson({
        ..._legacyScrutin,
        'count': count,
      })!.toJson();
      expect(_readerBefore8(json), isNotNull);
    });
  });

  group('arc dans l\'ordre de l\'hémicycle (#67)', () {
    // Scrutin 8706 : LFI-NFP, tout à gauche, s'abstient ; le reste vote pour.
    const arc = [
      {'position': 'abstention', 'n': 67},
      {'position': 'pour', 'n': 503},
    ];

    test('absent (index antérieur) : pas d\'arc', () {
      final d = DecisionSummary.tryFromJson(_legacyScrutin)!;
      expect(d.arc, isNull);
      expect(d.toJson(), isNot(contains('arc')));
    });

    test('aller-retour, ordre gardé', () {
      final d = DecisionSummary.tryFromJson({..._legacyScrutin, 'arc': arc})!;
      expect(d.arc, const [
        HemicycleSegment(ArcPosition.abstention, 67),
        HemicycleSegment(ArcPosition.pour, 503),
      ]);
      final json = _roundTrip(d.toJson()) as Map<String, Object?>;
      expect(json['arc'], arc);
      expect(DecisionSummary.tryFromJson(json)!.arc, d.arc);
    });

    test('un tronçon illisible rend l\'arc illisible, pas la décision', () {
      for (final bad in [
        [
          {'position': 'partage', 'n': 3},
          ...arc,
        ],
        [
          {'position': 'pour', 'n': 0},
        ],
        [
          {'position': 'pour', 'n': -2},
        ],
        [
          {'position': 'pour', 'n': '503'},
        ],
        [
          {'position': 'pour'},
        ],
        ['pour'],
        <Object?>[],
        {'position': 'pour', 'n': 1},
      ]) {
        final d = DecisionSummary.tryFromJson({..._legacyScrutin, 'arc': bad});
        expect(d, isNotNull, reason: '$bad');
        expect(d!.arc, isNull, reason: '$bad');
      }
    });

    test('conservé par withSummary et withCount, remplacé par withArc', () {
      final d = DecisionSummary.tryFromJson({..._legacyScrutin, 'arc': arc})!;
      expect(d.withSummary(null).arc, d.arc);
      expect(d.withCount(null).arc, d.arc);
      expect(d.withArc(null).arc, isNull);
      expect(d.withArc(null).toJson(), isNot(contains('arc')));
    });

    test('merge : tronçons vides retirés, voisins de même sens fusionnés', () {
      expect(
        HemicycleSegment.merge(const [
          HemicycleSegment(ArcPosition.abstention, 60),
          HemicycleSegment(ArcPosition.pour, 0),
          HemicycleSegment(ArcPosition.abstention, 7),
          HemicycleSegment(ArcPosition.pour, 17),
          HemicycleSegment(ArcPosition.pour, 486),
          HemicycleSegment(ArcPosition.contre, 2),
          HemicycleSegment(ArcPosition.pour, 1),
        ]),
        const [
          HemicycleSegment(ArcPosition.abstention, 67),
          HemicycleSegment(ArcPosition.pour, 503),
          HemicycleSegment(ArcPosition.contre, 2),
          HemicycleSegment(ArcPosition.pour, 1),
        ],
      );
      expect(HemicycleSegment.merge(const []), isEmpty);
    });

    test('lu sans erreur par une app antérieure', () {
      final json = DecisionSummary.tryFromJson({
        ..._legacyScrutin,
        'arc': arc,
      })!.toJson();
      expect(_readerBefore8(json), isNotNull);
      final index = DecisionIndex(
        generatedAt: DateTime.utc(2026, 10, 23),
        decisions: [DecisionSummary.tryFromJson(json)!],
      );
      // Même version de schéma : un ancien lecteur lit l'index.
      expect(
        DecisionIndex.fromJson(_roundTrip(index.toJson())).decisions.single.arc,
        hasLength(2),
      );
    });
  });
}
