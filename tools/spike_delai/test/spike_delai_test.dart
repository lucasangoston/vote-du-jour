import 'dart:io';

import 'package:spike_delai/src/classement.dart';
import 'package:spike_delai/src/dump.dart';
import 'package:spike_delai/src/heure_paris.dart';
import 'package:spike_delai/src/liste_site.dart';
import 'package:spike_delai/src/releve.dart';
import 'package:spike_delai/src/resume.dart';
import 'package:test/test.dart';

ScrutinSite site(int n, [String titre = "Scrutin public n°0 sur l'amendement n° 1"]) =>
    ScrutinSite(numero: n, titre: titre, seance: 'Première séance du mardi 20 octobre 2026');

void main() {
  group('classer', () {
    final cas = {
      "l'ensemble du projet de loi de finances pour 2027 (première lecture).": Categorie.ensemble,
      "l’ensemble de la proposition de loi relative au droit à l’aide à mourir": Categorie.ensemble,
      "Scrutin public n°12 sur l'ensemble du projet de loi": Categorie.ensemble,
      'la motion de censure déposée en application de l\'article 49, alinéa 3':
          Categorie.motionCensure,
      'la motion de rejet préalable, déposée par Mme Mathilde Panot': Categorie.autreMotion,
      'la déclaration du Gouvernement portant sur la stratégie de défense nationale':
          Categorie.declarationGouvernement,
      "l'amendement n° 3865 de Mme Olivia Grégoire après l'article 5": Categorie.amendement,
      "l’amendement n° 1972 de M. Davi à l’article 15": Categorie.amendement,
      "le sous-amendement n° 12 à l'amendement n° 3": Categorie.sousAmendement,
      "l'article 5 du projet de loi de finances pour 2027": Categorie.article,
      'la proposition de loi apportant une réponse intégrale (première lecture).':
          Categorie.nonClasse,
      'la déclaration de politique générale du Gouvernement de M. François Bayrou':
          Categorie.nonClasse,
    };
    cas.forEach((titre, attendu) {
      test(titre, () => expect(classer(titre), attendu));
    });
  });

  group('lireListe (fixture du 17/10/2026)', () {
    final liste = lireListe(File('test/fixtures/liste_scrutins.html').readAsStringSync());

    test('lit les 10 scrutins de la page, du plus récent au plus ancien', () {
      expect(liste.map((s) => s.numero), [for (var n = 8877; n > 8867; n--) n]);
    });

    test('décode le titre et la séance', () {
      expect(liste.first.titre,
          "Scrutin public n°8877 sur l'amendement n° 3865 de Mme Olivia Grégoire après l'article 5 du projet de loi de finances pour 2027 (première lecture).");
      expect(liste.first.seance, 'Troisième séance du vendredi 16 octobre 2026');
      expect(classer(liste.first.titre), Categorie.amendement);
    });

    test('signale une page sans scrutin', () {
      expect(() => lireListe('<html></html>'), throwsFormatException);
    });
  });

  group('lireDump (extrait réel)', () {
    final octets = File('test/fixtures/scrutins_extrait.zip').readAsBytesSync();

    test('liste les numéros sans décompresser', () {
      expect(numerosDuDump(octets), {1, 2104, 8705, 8876, 8877});
    });

    test('lit date, titre et type de vote', () {
      final s = lireDump(octets, seulement: {1, 8877});
      expect(s.map((x) => x.numero), [1, 8877]);
      expect(s.first.codeTypeVote, 'MOC');
      expect(classer(s.first.titre), Categorie.motionCensure);
      expect(s.last.dateScrutin, '2026-10-16');
      expect(s.last.sort, 'rejeté');
    });
  });

  group('integrerListe', () {
    final t0 = DateTime.utc(2026, 10, 20, 13);
    final t1 = t0.add(const Duration(minutes: 5));
    final t2 = t1.add(const Duration(minutes: 5));

    test('le premier passage fixe la référence sans rien relever', () {
      final etat = Etat();
      final releve = <LigneReleve>[];
      expect(integrerListe(etat, releve, [site(100), site(99)], t0), isEmpty);
      expect(etat.numeroReference, 100);
      expect(etat.dernierPassageReussi, t0);
    });

    test('relève les nouveaux numéros une seule fois, avec la fenêtre d\'apparition', () {
      final etat = Etat(numeroReference: 100, dernierPassageReussi: t0);
      final releve = <LigneReleve>[];
      final a = integrerListe(etat, releve, [site(102), site(101), site(100)], t1);
      expect(a.map((l) => l.numero), [101, 102]);
      expect(a.first.passagePrecedent, t0);
      expect(a.first.apparitionSite, t1);
      expect(a.first.categorie, 'amendement');

      final b = integrerListe(etat, releve, [site(103), site(102), site(101)], t2);
      expect(b.map((l) => l.numero), [103]);
      expect(b.single.passagePrecedent, t1);
      expect(releve.map((l) => l.numero), [101, 102, 103]);
    });

    test('détecte un débordement de page', () {
      final etat = Etat(numeroReference: 100, dernierPassageReussi: t0);
      expect(pageADebordement(etat, [], [site(160), site(150)]), isTrue);
      expect(pageADebordement(etat, [], [site(160), site(101)]), isFalse);
    });
  });

  test('integrerDump ne note que la première apparition', () {
    final lm1 = DateTime.utc(2026, 10, 21, 10, 30);
    final lm2 = DateTime.utc(2026, 10, 22, 10, 30);
    final releve = [
      LigneReleve(
        numero: 101,
        apparitionSite: lm1,
        passagePrecedent: null,
        seance: '',
        titre: '',
        categorie: 'amendement',
      ),
      LigneReleve(
        numero: 102,
        apparitionSite: lm1,
        passagePrecedent: null,
        seance: '',
        titre: '',
        categorie: 'amendement',
      ),
    ];
    expect(integrerDump(releve, {101: '2026-10-20'}, lm1), 1);
    expect(integrerDump(releve, {101: '2026-10-20', 102: '2026-10-20'}, lm2), 1);
    expect(releve[0].apparitionDump, lm1);
    expect(releve[1].apparitionDump, lm2);
    expect(releve[1].dateScrutin, '2026-10-20');
  });

  test('le relevé survit à un aller-retour sur disque', () {
    final dir = Directory.systemTemp.createTempSync('spike_delai');
    addTearDown(() => dir.deleteSync(recursive: true));
    final dossier = DossierDonnees(dir.path);
    final t = DateTime.utc(2026, 10, 20, 13, 5);
    final ligne = LigneReleve(
      numero: 8878,
      apparitionSite: t,
      passagePrecedent: t.subtract(const Duration(minutes: 5)),
      seance: 'Première séance du mardi 20 octobre 2026',
      titre: "l'ensemble du projet de loi, \"citation\"",
      categorie: 'ensemble',
    );
    dossier.ecrire(
        Etat(numeroReference: 8877, dumpLastModified: 'Tue, 20 Oct 2026 10:31:02 GMT'), [ligne]);
    dossier.ajouterPassage([isoUtc(t), 'ok', 1, 8878, 1, 'inchange', '']);

    final relu = dossier.lireReleve().single;
    expect(relu.titre, ligne.titre);
    expect(relu.passagePrecedent, ligne.passagePrecedent);
    expect(dossier.lireEtat().dumpLastModified, 'Tue, 20 Oct 2026 10:31:02 GMT');
    expect(dossier.lirePassages().single['statut'], 'ok');
  });

  group('heure de Paris', () {
    test('heure d\'été et d\'hiver', () {
      expect(formatParis(DateTime.utc(2026, 10, 20, 13)), '2026-10-20 15:00');
      expect(formatParis(DateTime.utc(2026, 10, 26, 13)), '2026-10-26 14:00');
      expect(depuisParis(DateTime(2026, 10, 20, 15)), DateTime.utc(2026, 10, 20, 13));
    });
  });

  test('resumer calcule le délai vote -> site', () {
    final vote = DateTime.utc(2026, 10, 20, 13, 2);
    final releve = [
      LigneReleve(
        numero: 8878,
        apparitionSite: DateTime.utc(2026, 10, 20, 13, 10),
        passagePrecedent: DateTime.utc(2026, 10, 20, 13, 5),
        seance: '',
        titre: "l'ensemble du projet de loi",
        categorie: 'ensemble',
      ),
    ];
    final texte = resumer(releve, [], {8878: vote});
    expect(texte, contains('médian 8 min'));
    expect(texte, contains('borne basse : médian 3 min'));
    expect(lireHeuresVote('numero,heure_vote_paris\n8878,2026-10-20 15:02\n'), {8878: vote});
  });
}
