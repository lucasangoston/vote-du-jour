import 'dart:io';

import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

import 'fixtures.dart';

/// Pages réelles du site de l'Assemblée, enregistrées le 18/10/2026 (voir
/// `test/fixtures/site/README.md`).
String sitePage(String name) =>
    File('test/fixtures/site/$name').readAsStringSync();

Classification classify(SiteScrutin s) =>
    classifyScrutin(titre: s.titre, codeTypeVote: null, sort: s.result!);

void main() {
  group('liste des 50 derniers scrutins (séance budgétaire du 16/10/2026)', () {
    late List<SiteScrutin> list;
    setUpAll(() => list = parseScrutinList(sitePage('liste_scrutins.html')));

    test('lit les 50 scrutins, du plus récent au plus ancien', () {
      expect(list.map((s) => s.numero), [for (var n = 8877; n > 8827; n--) n]);
    });

    test('intitulé sans le préfixe, séance, date, décompte et sort', () {
      final s = list.first;
      expect(s.uid, 'VTANR5L17V8877');
      expect(
        s.titre,
        "l'amendement n° 3865 de Mme Olivia Grégoire après l'article 5 du "
        'projet de loi de finances pour 2027 (première lecture).',
      );
      expect(s.seance, 'Troisième séance du vendredi 16 octobre 2026');
      expect(s.date, DateTime.utc(2026, 10, 16));
      expect((s.pour, s.contre, s.abstentions), (23, 25, 23));
      expect(s.result, VoteResult.rejete);
    });

    test('scrutin adopté', () {
      final s = list.firstWhere((s) => s.numero == 8876);
      expect(
        s.titre,
        "l'article 5 du projet de loi de finances pour 2027 (première "
        'lecture).',
      );
      expect(s.result, VoteResult.adopte);
      expect((s.pour, s.contre, s.abstentions), (25, 23, 23));
    });

    test('tous les scrutins ont un sort et un décompte', () {
      for (final s in list) {
        expect(s.result, isNotNull, reason: '${s.numero}');
        expect(s.pour, isNotNull, reason: '${s.numero}');
        expect(s.date, isNotNull, reason: '${s.numero}');
      }
    });

    test('amendements et articles : aucune décision pour le sélecteur', () {
      for (final s in list) {
        expect(classify(s), isA<Excluded>(), reason: s.titre);
      }
    });
  });

  group('scrutins solennels (liste filtrée)', () {
    late Map<int, SiteScrutin> byNumero;
    setUpAll(() {
      byNumero = {
        for (final s in parseScrutinList(
          sitePage('liste_scrutins_solennels.html'),
        ))
          s.numero: s,
      };
    });

    test('même intitulé que le jeu de données', () {
      for (final n in [8705, 8706]) {
        final dump = parseScrutinJson(fixtureFile(n).readAsStringSync());
        final site = byNumero[n]!;
        expect(site.titre, dump.titre);
        expect(site.date, dump.date);
        expect(site.result, dump.result);
        expect(
          (site.pour, site.contre, site.abstentions),
          (dump.decompte.pour, dump.decompte.contre, dump.decompte.abstentions),
        );
      }
    });

    test('vote sur l\'ensemble retenu par le sélecteur', () {
      expect(
        classify(byNumero[8706]!),
        const Retained(DecisionType.ensembleTexte, VoteResult.adopte),
      );
    });
  });

  group('motions de censure (liste filtrée)', () {
    late List<SiteScrutin> list;
    setUpAll(
      () => list = parseScrutinList(sitePage('liste_motions_censure.html')),
    );

    test('reconnues par l\'intitulé, sans le type de vote', () {
      expect(list, hasLength(7));
      for (final s in list) {
        expect(
          classify(s),
          const Retained(DecisionType.motionDeCensure, VoteResult.rejete),
        );
      }
    });

    test('même intitulé que le jeu de données (5731)', () {
      final dump = parseScrutinJson(fixtureFile(5731).readAsStringSync());
      final site = list.firstWhere((s) => s.numero == 5731);
      expect(site.titre, dump.titre);
      expect(site.date, dump.date);
      expect(site.pour, dump.decompte.pour);
    });

    test('seules les voix pour sont affichées', () {
      final s = list.firstWhere((s) => s.numero == 7979);
      expect(s.pour, 132);
      expect(s.contre, isNull);
      expect(s.date, DateTime.utc(2026, 7, 6));
      expect(s.seance, 'Unique séance du lundi 6 juillet 2026');
    });
  });

  test('page d\'un scrutin : mêmes informations que la liste', () {
    final page = parseScrutinPage(sitePage('scrutin_8706.html'), numero: 8706);
    final listed = parseScrutinList(
      sitePage('liste_scrutins_solennels.html'),
    ).firstWhere((s) => s.numero == 8706);
    expect(page.toJson(), listed.toJson());
  });

  test('complète un scrutin de la liste par sa page', () {
    const partial = SiteScrutin(numero: 8706, titre: 'la proposition…');
    final page = parseScrutinPage(sitePage('scrutin_8706.html'), numero: 8706);
    final s = partial.completedWith(page);
    expect(s.titre, 'la proposition…');
    expect(s.result, VoteResult.adopte);
    expect(s.pour, 503);
    expect(s.date, DateTime.utc(2026, 10, 13));
  });

  group('structure inconnue', () {
    test('page sans bloc de scrutin', () {
      expect(() => parseScrutinList('<html></html>'), throwsFormatException);
    });

    test('bloc sans lien vers le scrutin', () {
      expect(
        () => parseScrutinList(
          '<div class="an-bloc _style-scrutin"><a href="/x">?</a></div>',
        ),
        throwsFormatException,
      );
    });

    test('intitulé sans « Scrutin public n° »', () {
      expect(
        () => parseScrutinList(
          '<div class="an-bloc _style-scrutin">'
          '<a class="link h6" href="/dyn/17/scrutins/12">Vote 12</a></div>',
        ),
        throwsFormatException,
      );
    });

    test('page de scrutin sans intitulé', () {
      expect(
        () => parseScrutinPage('<html></html>', numero: 1),
        throwsFormatException,
      );
    });
  });

  test('date de séance', () {
    expect(
      seanceDate('Première séance du jeudi 1er octobre 2026'),
      DateTime.utc(2026, 10, 1),
    );
    expect(
      seanceDate('Deuxième séance du mardi 3 février 2026'),
      DateTime.utc(2026, 2, 3),
    );
    expect(seanceDate('Séance'), isNull);
  });

  test('aller-retour JSON (état de la détection)', () {
    final s = parseScrutinList(sitePage('liste_motions_censure.html')).first;
    expect(SiteScrutin.fromJson(s.toJson()).toJson(), s.toJson());
  });
}
