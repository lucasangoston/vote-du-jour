import 'dart:io';

import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

import 'fixtures.dart';

const _dossierUrl = 'https://www.assemblee-nationale.fr/dyn/17/dossiers/';

/// Scrutins sur l'article unique d'un texte (#22), sur de vraies fixtures :
/// voir `test/fixtures/scrutins/README.md`.
void main() {
  late List<Scrutin> scrutins;
  late DecisionIndex index;

  setUpAll(() {
    scrutins = readScrutinsArchive(
      fixtureArchive(numeros: [...fixtureNumeros, ...articleUniqueNumeros]),
    );
    index = buildDecisionIndex(
      scrutins,
      generatedAt: DateTime.utc(2026, 10, 17),
      dossiers: DossierIndex.fromArchive(
        fixtureDossiersArchive(
          extra: {
            'json/dossierParlementaire/DLR5L17N52700.json': File(
              'test/fixtures/dossiers/article_unique/DLR5L17N52700.json',
            ).readAsStringSync(),
          },
        ),
      ),
      limit: 1000,
    );
  });

  DecisionSummary? byNumero(int numero) =>
      index.decisions.where((d) => d.numero == numero).firstOrNull;

  group('retenu comme vote sur l\'ensemble', () {
    test('proposition de loi (2633, registre des cancers)', () {
      // Non rattaché dans les fixtures (titre du dossier DLR5L16N47676
      // différent, sans son document) : libellés tirés de l'intitulé.
      final d = byNumero(2633)!;
      expect(d.id, 'VTANR5L17V2633');
      expect(d.type, DecisionType.ensembleTexte);
      expect(d.result, VoteResult.adopte);
      expect(d.voteMode, VoteMode.scrutinPublic);
      expect(
        d.shortTitle,
        'Proposition de loi visant à mettre en place un registre national des '
        'cancers',
      );
      expect(d.stage, "1re lecture à l'AN");
    });

    test('proposition de résolution rattachée à son dossier, qui cite le '
        'scrutin (7349)', () {
      final d = byNumero(7349)!;
      expect(d.type, DecisionType.resolution);
      expect(d.stage, resolutionLabel);
      expect(d.dossierUrl, '${_dossierUrl}DLR5L17N52700');
      expect(
        d.shortTitle,
        'Évaluer précisément le coût réel et sociétal de l’insécurité routière '
        'et son impact sur les finances publiques',
      );
    });

    test('résolution européenne non rattachée : titre tiré de l\'intitulé '
        '(691, Mercosur)', () {
      final d = byNumero(691)!;
      expect(d.type, DecisionType.resolution);
      expect(d.stage, resolutionLabel);
      expect(d.dossierUrl, isNull);
      expect(
        d.shortTitle,
        "Proposition de résolution européenne visant à refuser la ratification "
        "de l'accord commercial entre l'Union européenne et le Mercosur",
      );
    });

    test('article unique rejeté : le texte est rejeté (1333)', () {
      final d = byNumero(1333)!;
      expect(d.type, DecisionType.ensembleTexte);
      expect(d.result, VoteResult.rejete);
      expect(d.stage, "1re lecture à l'AN");
      expect(
        d.shortTitle,
        startsWith('Projet de loi autorisant la ratification'),
      );
    });
  });

  group('pas de doublon avec un vote sur l\'ensemble distinct', () {
    test('ensemble voté le même jour : seul l\'ensemble est publié '
        '(930 puis 931)', () {
      expect(byNumero(930), isNull);
      expect(byNumero(931), isNotNull);
    });

    test('même chose pour une résolution européenne (684 puis 685)', () {
      expect(byNumero(684), isNull);
      expect(byNumero(685)!.type, DecisionType.resolution);
    });

    test('ensemble d\'un autre texte le même jour : article unique gardé '
        '(691 et 685)', () {
      expect(byNumero(691), isNotNull);
      expect(byNumero(685), isNotNull);
    });

    test('ensemble reporté à un scrutin solennel la semaine suivante '
        '(6902 puis 7260)', () {
      expect(byNumero(6902), isNull);
      expect(byNumero(7260)!.stage, "2e lecture à l'AN");
    });

    test('ensemble voté dans une autre lecture : article unique gardé', () {
      // 6902 (deuxième lecture) suivi d'un vote sur l'ensemble du même texte
      // en nouvelle lecture (intitulé de 7260 adapté).
      final articleUnique = scrutins.firstWhere((s) => s.numero == 6902);
      final ensemble = scrutins.firstWhere((s) => s.numero == 7260);
      final later = _withTitle(
        ensemble,
        ensemble.titre.replaceFirst('(deuxième lecture)', '(nouvelle lecture)'),
      );
      final i = buildDecisionIndex([
        articleUnique,
        later,
      ], generatedAt: DateTime.utc(2026, 10, 17));
      expect(i.decisions.map((d) => d.numero), [7260, 6902]);
    });

    test('le texte apparaît une seule fois, en scrutin public, et non à '
        'main levée (2633)', () {
      final registre = index.decisions.where(
        (d) => d.officialTitle.contains('registre national des cancers'),
      );
      expect(registre.map((d) => d.id), ['VTANR5L17V2633']);
      expect(index.decisions.where((d) => d.id == 'L17-VD226757DEC'), isEmpty);
    });

    test('les décisions à main levée des fixtures ne changent pas', () {
      expect(
        [
          for (final d in index.decisions)
            if (d.voteMode == VoteMode.mainLevee) d.id,
        ],
        ['L17-VD234087DEC', 'L17-VD230548DEC', 'L17-VD224512DEC'],
      );
    });
  });
}

Scrutin _withTitle(Scrutin s, String titre) => Scrutin(
  uid: s.uid,
  numero: s.numero,
  date: s.date,
  titre: titre,
  codeTypeVote: s.codeTypeVote,
  libelleTypeVote: s.libelleTypeVote,
  result: s.result,
  decompte: s.decompte,
  dossierRef: null,
  groupVotes: s.groupVotes,
);
