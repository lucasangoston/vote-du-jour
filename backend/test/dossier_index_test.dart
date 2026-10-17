import 'dart:convert';

import 'package:test/test.dart';
import 'package:vote_job/vote_job.dart';

import 'fixtures.dart';

void main() {
  late DossierIndex index;
  late Map<int, Scrutin> scrutins;

  setUpAll(() {
    index = DossierIndex.fromArchive(fixtureDossiersArchive());
    scrutins = {
      for (final s in readScrutinsArchive(fixtureArchive())) s.numero: s,
    };
  });

  DossierLink? linkOf(int numero) {
    final s = scrutins[numero]!;
    return index.link(
      scrutinUid: s.uid,
      date: s.date,
      titre: s.titre,
      dossierRef: s.dossierRef,
    );
  }

  group('lecture de l\'index des dossiers (fixtures réelles)', () {
    test('lit chaque dossier de l\'archive', () {
      expect(index.length, 13);
    });

    test('lit le titre du dossier (titreDossier.titre)', () {
      expect(
        index.dossier('DLR5L17N50169')!.title,
        'Proposition de loi visant à sortir la France du piège du narcotrafic',
      );
      expect(
        index.dossier('DLR5L17N50169')!.url,
        'https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N50169',
      );
      expect(index.dossier('DLR5L17N00000'), isNull);
    });

    test('ignore les fichiers qui ne sont ni dossiers ni documents', () {
      final withNoise = DossierIndex.fromArchive(
        fixtureDossiersArchive(extra: {'LISEZMOI.txt': 'rien'}),
      );
      expect(withNoise.length, 13);
    });

    test('un document illisible est ignoré', () {
      final withBadDoc = DossierIndex.fromArchive(
        fixtureDossiersArchive(extra: {'json/document/X.json': '{"doc'}),
      );
      expect(withBadDoc.length, 13);
    });

    test('un dossier sans titre est signalé', () {
      expect(
        () => DossierIndex.fromArchive(
          fixtureDossiersArchive(
            extra: {
              'json/dossierParlementaire/DLR5L17N1.json': jsonEncode({
                'dossierParlementaire': {'uid': 'DLR5L17N1'},
              }),
            },
          ),
        ),
        throwsA(
          isA<DumpFormatException>().having(
            (e) => e.message,
            'message',
            contains('titreDossier.titre'),
          ),
        ),
      );
    });

    test('se relit à l\'identique depuis son cache JSON', () {
      final cached = DossierIndex.fromJson(
        jsonDecode(jsonEncode(index.toJson())),
      );
      expect(cached.length, index.length);
      for (final n in fixtureNumeros) {
        final s = scrutins[n]!;
        final a = linkOf(n);
        final b = cached.link(
          scrutinUid: s.uid,
          date: s.date,
          titre: s.titre,
          dossierRef: s.dossierRef,
        );
        expect(b?.dossier.uid, a?.dossier.uid, reason: 'scrutin $n');
        expect(b?.lecture, a?.lecture, reason: 'scrutin $n');
        expect(b?.isText, a?.isText, reason: 'scrutin $n');
      }
    });

    test('refuse un cache d\'une autre version', () {
      expect(
        () => DossierIndex.fromJson({'version': 99}),
        throwsFormatException,
      );
    });
  });

  group('association décision ↔ dossier', () {
    test(
      'par le scrutin cité dans les actes du dossier (217, 1re lecture)',
      () {
        final link = linkOf(217)!;
        expect(link.dossier.uid, 'DLR5L17N50453');
        expect(link.lecture, Lecture.premiere);
        expect(link.isText, isTrue);
      },
    );

    test('2e lecture, nouvelle lecture, lecture définitive, CMP', () {
      expect(linkOf(504)!.lecture, Lecture.deuxieme);
      expect(linkOf(4696)!.lecture, Lecture.nouvelle);
      expect(linkOf(4758)!.lecture, Lecture.definitive);
      expect(linkOf(4696)!.dossier.uid, 'DLR5L17N52922');
      expect(linkOf(2278)!.lecture, Lecture.commissionMixteParitaire);
    });

    test('résolution en lecture unique (1018)', () {
      final link = linkOf(1018)!;
      expect(link.dossier.uid, 'DLR5L17N51279');
      expect(link.lecture, Lecture.unique);
    });

    test('motion de censure après 49.3 : le dossier du texte plutôt que '
        'l\'engagement de responsabilité (519)', () {
      final link = linkOf(519)!;
      expect(link.dossier.uid, 'DLR5L17N50588');
      expect(link.isText, isTrue);
    });

    test('motion de censure (49.2) : dossier sans texte (5731)', () {
      final link = linkOf(5731)!;
      expect(link.dossier.uid, 'DLR5L17N53822');
      expect(link.isText, isFalse);
    });

    test('par la référence de dossier du scrutin, lecture du jour (6346)', () {
      final s = scrutins[6346]!;
      expect(s.dossierRef, 'DLR5L17N52635');
      final link = linkOf(6346)!;
      expect(link.dossier.uid, 'DLR5L17N52635');
      expect(link.lecture, Lecture.commissionMixteParitaire);
    });

    test('par l\'intitulé, confirmé par une décision le jour même (1194)', () {
      expect(scrutins[1194]!.dossierRef, isNull);
      final link = linkOf(1194)!;
      expect(link.dossier.uid, 'DLR5L17N50169');
      expect(link.lecture, Lecture.premiere);
    });

    test('par le titre d\'un document du dossier (289)', () {
      final link = linkOf(289)!;
      expect(link.dossier.uid, 'DLR5L16N47722');
      expect(link.lecture, Lecture.commissionMixteParitaire);
    });

    test(
      'un intitulé homonyme sans décision ce jour-là n\'est pas rattaché',
      () {
        final s = scrutins[1194]!;
        expect(
          index.link(
            scrutinUid: 'VTANR5L17V999999',
            date: DateTime.utc(2030, 1, 1),
            titre: s.titre,
          ),
          isNull,
        );
      },
    );

    test('déclaration du Gouvernement : aucun dossier (4802, 3054)', () {
      expect(linkOf(4802), isNull);
      expect(linkOf(3054), isNull);
    });
  });

  group('lecture indiquée par l\'intitulé', () {
    test('reconnaît les parenthèses finales', () {
      expect(
        Lecture.fromScrutinTitle(
          'l\'ensemble du projet de loi (première lecture).',
        ),
        Lecture.premiere,
      );
      expect(
        Lecture.fromScrutinTitle(
          'l’ensemble de la proposition de loi X (texte de la commission mixte paritaire).',
        ),
        Lecture.commissionMixteParitaire,
      );
      expect(
        Lecture.fromScrutinTitle(
          'l\'ensemble du projet de loi (lecture définitive).',
        ),
        Lecture.definitive,
      );
      expect(
        Lecture.fromScrutinTitle(
          'la déclaration du Gouvernement (application de l\'article 50-1 de la Constitution).',
        ),
        isNull,
      );
    });
  });
}
