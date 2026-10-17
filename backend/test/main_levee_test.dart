import 'dart:convert';

import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

import 'fixtures.dart';

const _dossierUrl = 'https://www.assemblee-nationale.fr/dyn/17/dossiers/';

void main() {
  late DossierIndex dossiers;
  late List<Scrutin> scrutins;
  late DecisionIndex index;

  setUpAll(() {
    dossiers = DossierIndex.fromArchive(fixtureDossiersArchive());
    scrutins = readScrutinsArchive(fixtureArchive());
    index = buildDecisionIndex(
      scrutins,
      generatedAt: DateTime.utc(2026, 10, 17),
      dossiers: dossiers,
    );
  });

  List<DecisionSummary> mainLevee(DecisionIndex i) => [
    for (final d in i.decisions)
      if (d.voteMode == VoteMode.mainLevee) d,
  ];

  group('détection dans les dossiers (fixtures réelles)', () {
    test('actes de décision de l\'Assemblée, adoptés, sans voteRef', () {
      expect(dossiers.mainLeveeAdoptions().map((a) => a.acteUid).toSet(), {
        'L17-VD224904DEC', // DLR5L17N50169, scrutin 1194 non cité
        'L17-VD231814DEC', // DLR5L17N52635, CMP, scrutin 6346 non cité
        'L17-VD234087DEC', // DLR5L17N54379, convention
        'L17-VD230548DEC', // DLR5L17N53201, résolution
        'L17-VD224512DEC', // DLR5L16N49852
        'L17-VD226757DEC', // DLR5L16N47676, article unique 2633
        'L17-VD227011DEC', // DLR5L17N52002, scrutin 2900 non rattaché
      });
    });

    test('écarte le Sénat, les rejets, le 49.3 et les actes cités par un '
        'scrutin', () {
      final uids = dossiers.mainLeveeAdoptions().map((a) => a.acteUid);
      expect(
        uids,
        isNot(
          anyOf(
            contains('L17-VD222094DEC'), // CMP-DEBATS-DEC, Sénat
            contains('L17-VD221945DEC'), // rejetée
            contains('L17-VD223800DEC'), // considéré comme adopté (49.3)
            contains('L17-VD222686DEC'), // considéré comme rejeté (49.3)
            contains('L17-VD224301DEC'), // adoptée, cite un scrutin
          ),
        ),
      );
    });

    test('écarte les actes antérieurs à la 17e législature', () {
      final all = dossiers.mainLeveeAdoptions(since: DateTime.utc(2000));
      final recent = dossiers.mainLeveeAdoptions();
      expect(all.length, greaterThanOrEqualTo(recent.length));
      expect(
        recent.every((a) => !a.date.isBefore(DateTime.utc(2024, 7, 18))),
        isTrue,
      );
    });

    test('convention : lecture, jour et intitulé du texte adopté', () {
      final a = dossiers.mainLeveeAdoptions().firstWhere(
        (a) => a.acteUid == 'L17-VD234087DEC',
      );
      expect(a.dossier.uid, 'DLR5L17N54379');
      expect(a.lecture, Lecture.premiere);
      expect(a.date, DateTime.utc(2026, 10, 7));
      expect(a.isResolution, isFalse);
      expect(
        a.officialTitle,
        "projet de loi autorisant l'approbation de l'accord multilatéral "
        'entre autorités compétentes portant sur l\'échange des informations '
        'GloBE',
      );
    });

    test('résolution sans document : intitulé du dossier', () {
      final a = dossiers.mainLeveeAdoptions().firstWhere(
        (a) => a.acteUid == 'L17-VD230548DEC',
      );
      expect(a.isResolution, isTrue);
      expect(a.lecture, Lecture.unique);
      expect(a.textTitle, isNull);
      expect(a.officialTitle, a.dossier.title);
    });

    test('se relit à l\'identique depuis le cache JSON', () {
      final cached = DossierIndex.fromJson(
        jsonDecode(jsonEncode(dossiers.toJson())),
      );
      String describe(MainLeveeAdoption a) =>
          '${a.acteUid} ${a.dossier.uid} ${a.lecture} ${a.date} '
          '${a.isResolution} ${a.officialTitle}';
      expect(
        cached.mainLeveeAdoptions().map(describe),
        dossiers.mainLeveeAdoptions().map(describe),
      );
    });

    test('un cache de version 1 (avant le ticket #8) est refusé', () {
      final v1 = dossiers.toJson()
        ..['version'] = 1
        ..remove('adoptions');
      expect(() => DossierIndex.fromJson(v1), throwsFormatException);
    });
  });

  group('publication', () {
    test('publie les textes adoptés à main levée, sans numéro', () {
      final convention = index.decisions.firstWhere(
        (d) => d.id == 'L17-VD234087DEC',
      );
      expect(convention.voteMode, VoteMode.mainLevee);
      expect(convention.numero, isNull);
      expect(convention.type, DecisionType.ensembleTexte);
      expect(convention.result, VoteResult.adopte);
      expect(convention.status, DecisionStatus.confirmee);
      expect(convention.date, DateTime.utc(2026, 10, 7));
      expect(convention.stage, "1re lecture à l'AN");
      expect(
        convention.shortTitle,
        'Projet de loi autorisant l’approbation de l’accord multilatéral '
        'entre autorités compétentes portant sur l’échange des informations '
        'GloBE',
      );
      expect(convention.sourceUrl, '${_dossierUrl}DLR5L17N54379');
      expect(convention.dossierUrl, '${_dossierUrl}DLR5L17N54379');

      final resolution = index.decisions.firstWhere(
        (d) => d.id == 'L17-VD230548DEC',
      );
      expect(resolution.type, DecisionType.resolution);
      expect(resolution.stage, resolutionLabel);
      expect(
        resolution.shortTitle,
        'Renforcer le pilotage et la cohérence de la politique nationale du '
        'sport',
      );
    });

    test('des scrutins publics sur les articles n\'empêchent pas la main '
        'levée sur l\'ensemble (1011)', () {
      final d = index.decisions.firstWhere((d) => d.id == 'L17-VD224512DEC');
      expect(d.voteMode, VoteMode.mainLevee);
      expect(
        d.shortTitle,
        'Lutter contre les fermetures abusives de comptes '
        'bancaires',
      );
    });

    test('sans dossiers, aucun vote à main levée', () {
      final without = buildDecisionIndex(
        scrutins,
        generatedAt: DateTime.utc(2026, 10, 17),
      );
      expect(mainLevee(without), isEmpty);
    });
  });

  group('pas de doublon avec un scrutin public', () {
    test('seuls trois textes de fixtures sont publiés à main levée', () {
      expect(mainLevee(index).map((d) => d.id), [
        'L17-VD234087DEC',
        'L17-VD230548DEC',
        'L17-VD224512DEC',
      ]);
    });

    test('scrutin rattaché au dossier par l\'intitulé (1194)', () {
      final narcotrafic = index.decisions.where(
        (d) => d.dossierUrl == '${_dossierUrl}DLR5L17N50169',
      );
      expect(narcotrafic.map((d) => d.id), ['VTANR5L17V1194']);
    });

    test('scrutin rattaché par sa référence de dossier (6346)', () {
      final restitution = index.decisions.where(
        (d) => d.dossierUrl == '${_dossierUrl}DLR5L17N52635',
      );
      expect(restitution.map((d) => d.id), ['VTANR5L17V6346']);
    });

    test('scrutin sur l\'article unique, qui vaut vote sur l\'ensemble '
        '(2633)', () {
      expect(index.decisions.where((d) => d.id == 'L17-VD226757DEC'), isEmpty);
    });

    test('scrutin non rattaché, même texte à quelques mots près (2900)', () {
      expect(index.decisions.where((d) => d.id == 'L17-VD227011DEC'), isEmpty);
      expect(
        index.decisions.where((d) => d.id == 'VTANR5L17V2900'),
        hasLength(1),
      );
    });
  });

  group('intitulés d\'un même texte', () {
    test('reconnaît de légères variations (cas réels)', () {
      expect(
        sameVotedText(
          "l'ensemble du projet de loi portant création de l'établissement "
          "public du commerce et de l'industrie de Corse (première lecture).",
          [
            'Projet de loi portant création de l’établissement public du '
                'commerce et de l’industrie de la collectivité de Corse',
          ],
        ),
        isTrue,
      );
      expect(
        sameVotedText(
          'la proposition de résolution visant à la reconnaissance, au '
          'remboursement et à la réparation par la France de la "double '
          'dette" d\'Haiti.',
          [
            'résolution visant à la reconnaissance, au remboursement et à la '
                'réparation par la France de la "double dette" d\'Haïti',
          ],
        ),
        isTrue,
      );
      expect(
        sameVotedText(
          "l'ensemble de la proposition de loi relative à la sûreté dans les "
          'transports (première lecture).',
          [
            'Proposition de loi relative au renforcement de la sûreté dans les '
                'transports',
          ],
        ),
        isTrue,
      );
    });

    test('distingue deux conventions de même formule', () {
      expect(
        sameVotedText(
          "l'ensemble du projet de loi autorisant l'approbation de l'accord "
          'entre le Gouvernement de la République française et le '
          'Gouvernement de la République de Djibouti relatif à la défense '
          '(première lecture).',
          [
            'Projet de loi autorisant l’approbation de l’accord entre le '
                'Gouvernement de la République française et le Gouvernement '
                'du Royaume du Cambodge relatif à l’extradition',
          ],
        ),
        isFalse,
      );
    });

    test('un intitulé qui ne nomme pas de texte ne correspond à rien', () {
      expect(
        sameVotedText('la motion de censure déposée par M. X.', ['Motion']),
        isFalse,
      );
    });
  });

  group('tri et limite', () {
    test('trié par date avec les scrutins publics', () {
      final dates = index.decisions.map((d) => d.date).toList();
      for (var i = 1; i < dates.length; i++) {
        expect(dates[i].isAfter(dates[i - 1]), isFalse, reason: 'rang $i');
      }
      final ids = index.decisions.map((d) => d.id).toList();
      // 2026-10-07 : plus récent que tous les scrutins des fixtures.
      expect(ids.first, 'L17-VD234087DEC');
      // 2026-02-16, entre la motion de censure du 2026-02-25 et le scrutin
      // 4758 du 2025-12-16.
      expect(ids.indexOf('L17-VD230548DEC'), ids.indexOf('VTANR5L17V5731') + 1);
    });

    test('à date égale, le scrutin public d\'abord', () {
      DecisionSummary d(String id, {int? numero}) => DecisionSummary(
        id: id,
        numero: numero,
        voteMode: numero == null ? VoteMode.mainLevee : VoteMode.scrutinPublic,
        type: DecisionType.ensembleTexte,
        status: DecisionStatus.confirmee,
        result: VoteResult.adopte,
        date: DateTime.utc(2026, 10, 13),
        officialTitle: id,
        sourceUrl: 'https://example.org/$id',
      );
      final sorted = [
        d('L17-VD1DEC'),
        d('VTANR5L17V10', numero: 10),
        d('L17-VD2DEC'),
        d('VTANR5L17V11', numero: 11),
      ]..sort(compareDecisions);
      expect(sorted.map((d) => d.id), [
        'VTANR5L17V11',
        'VTANR5L17V10',
        'L17-VD2DEC',
        'L17-VD1DEC',
      ]);
    });

    test('l\'index garde les 50 décisions les plus récentes au total', () {
      final many = [
        for (var i = 1; i <= 80; i++)
          Scrutin(
            uid: 'VTANR5L17V$i',
            numero: i,
            // 2026-01-01 → 2026-02-10 : entre les votes à main levée du
            // 2025-03-13 et du 2026-02-16.
            date: DateTime.utc(2026, 1, 1).add(Duration(days: i ~/ 2)),
            titre: "l'ensemble du projet de loi n° $i (première lecture).",
            codeTypeVote: 'SPO',
            libelleTypeVote: 'scrutin public ordinaire',
            result: VoteResult.adopte,
            decompte: const Decompte(
              pour: 1,
              contre: 0,
              abstentions: 0,
              nonVotants: 0,
            ),
            dossierRef: null,
            groupVotes: const [],
          ),
      ];
      final limited = buildDecisionIndex(
        many,
        generatedAt: DateTime.utc(2026, 10, 17),
        dossiers: dossiers,
      );
      expect(limited.decisions, hasLength(maxIndexDecisions));
      expect(limited.decisions.map((d) => d.id), [
        'L17-VD234087DEC', // 2026-10-07
        // 2026-05-06 : sans le scrutin 6346 qui l'a adopté, l'acte de la
        // CMP, qui ne cite aucun scrutin, passe pour un vote à main levée.
        'L17-VD231814DEC',
        'L17-VD230548DEC', // 2026-02-16
        for (var i = 80; i > 33; i--) 'VTANR5L17V$i',
      ]);
    });
  });
}
