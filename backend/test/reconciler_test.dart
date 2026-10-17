import 'dart:convert';

import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

import 'fixtures.dart';

Scrutin dumpScrutin(int n) =>
    parseScrutinJson(fixtureFile(n).readAsStringSync());

/// Le scrutin [n] tel que le lit la détection en direct : l'intitulé, la
/// date, le sort et le décompte du site, sans type de vote, dossier ni vote
/// par groupe.
Scrutin asProvisional(int n) {
  final s = dumpScrutin(n);
  return SiteScrutin(
    numero: s.numero,
    titre: s.titre,
    result: s.result,
    pour: s.decompte.pour,
    contre: s.decompte.contre,
    abstentions: s.decompte.abstentions,
    date: s.date,
  ).toScrutin(fallbackDate: s.date);
}

String encode(DecisionIndex index) => jsonEncode(index.toJson());

void main() {
  final generatedAt = DateTime.utc(2026, 10, 20, 15);
  final dump = readScrutinsArchive(fixtureArchive());

  test('dump seul : exactement l\'index de buildDecisionIndex', () {
    final r = reconcile(confirmed: dump, generatedAt: generatedAt);
    expect(
      encode(r.index),
      encode(buildDecisionIndex(dump, generatedAt: generatedAt)),
    );
    expect(r.pending, isEmpty);
    expect(r.index.decisions.map((d) => d.status).toSet(), {
      DecisionStatus.confirmee,
    });
  });

  test('provisoire, puis confirmée par le jeu de données', () {
    // Mardi : 8706 est sur le site, pas encore dans le jeu de données.
    final before = reconcile(
      confirmed: dump,
      provisional: [asProvisional(8706)],
      generatedAt: generatedAt,
    );
    final top = before.index.decisions.first;
    expect(top.id, 'VTANR5L17V8706');
    expect(top.status, DecisionStatus.provisoire);
    expect(top.type, DecisionType.ensembleTexte);
    expect(top.result, VoteResult.adopte);
    expect(top.date, DateTime.utc(2026, 10, 13));
    expect(top.stage, "1re lecture à l'AN");
    expect(before.index.decisions.skip(1).map((d) => d.status).toSet(), {
      DecisionStatus.confirmee,
    });
    expect(before.pending.map((s) => s.numero), [8706]);

    // Mercredi : le jeu de données le contient.
    final withDump = [...dump, dumpScrutin(8705), dumpScrutin(8706)];
    final after = reconcile(
      confirmed: withDump,
      provisional: [asProvisional(8706)],
      generatedAt: generatedAt,
    );
    expect(after.pending, isEmpty);
    expect(
      encode(after.index),
      encode(buildDecisionIndex(withDump, generatedAt: generatedAt)),
    );
    expect(after.index.decisions.first.status, DecisionStatus.confirmee);
  });

  test('une provisoire absente du jeu de données reste provisoire', () {
    // Le jeu de données du lendemain s'arrête avant 8706 (vote du soir).
    final r = reconcile(
      confirmed: [...dump, dumpScrutin(8705)],
      provisional: [asProvisional(8705), asProvisional(8706)],
      generatedAt: generatedAt,
    );
    expect(r.pending.map((s) => s.numero), [8706]);
    expect(
      [for (final d in r.index.decisions.take(2)) (d.numero, d.status)],
      [(8706, DecisionStatus.provisoire), (8705, DecisionStatus.confirmee)],
    );
  });

  test('le jeu de données est complet jusqu\'à son dernier numéro', () {
    // Un scrutin provisoire de numéro inférieur est confirmé, même s'il
    // n'est pas dans les scrutins gardés (instantané filtré).
    final r = reconcile(
      confirmed: dump,
      confirmedUpTo: 8706,
      provisional: [asProvisional(8706)],
      generatedAt: generatedAt,
    );
    expect(r.pending, isEmpty);
    expect(
      r.index.decisions.map((d) => d.id),
      isNot(contains('VTANR5L17V8706')),
    );
  });

  group('mêmes règles que le jeu de données', () {
    // Jeu de données arrêté avant les scrutins rejoués comme provisoires.
    List<Scrutin> dumpBefore(int numero) => [
      for (final s in dump)
        if (s.numero < numero) s,
    ];

    test('article unique suivi du vote sur l\'ensemble (#22)', () {
      final r = reconcile(
        confirmed: dumpBefore(930),
        provisional: [asProvisional(930), asProvisional(931)],
        generatedAt: generatedAt,
      );
      expect(r.index.decisions.first.numero, 931);
      expect(r.index.decisions.first.status, DecisionStatus.provisoire);
      expect(r.index.decisions.map((d) => d.numero), isNot(contains(930)));
    });

    test('article unique seul : publié comme vote sur l\'ensemble', () {
      final r = reconcile(
        confirmed: dumpBefore(930),
        provisional: [asProvisional(930)],
        generatedAt: generatedAt,
      );
      final d = r.index.decisions.first;
      expect(
        (d.numero, d.type, d.status),
        (930, DecisionType.ensembleTexte, DecisionStatus.provisoire),
      );
    });

    test('rattachement au dossier par l\'intitulé', () {
      final dossiers = DossierIndex.fromArchive(fixtureDossiersArchive());
      final confirmed = buildDecisionIndex(
        dump,
        generatedAt: generatedAt,
        dossiers: dossiers,
      ).decisions.firstWhere((d) => d.numero == 1194);
      final r = reconcile(
        confirmed: dumpBefore(1194),
        provisional: [asProvisional(1194)],
        generatedAt: generatedAt,
        dossiers: dossiers,
      );
      final provisional = r.index.decisions.firstWhere((d) => d.numero == 1194);
      expect(provisional.status, DecisionStatus.provisoire);
      expect(provisional.dossierUrl, isNotNull);
      expect({
        ...provisional.toJson(),
        'status': 'confirmee',
      }, confirmed.toJson());
    });

    test('amendement : jamais publié', () {
      final r = reconcile(
        confirmed: dumpBefore(3022),
        provisional: [asProvisional(3022)],
        generatedAt: generatedAt,
      );
      expect(r.index.decisions.map((d) => d.numero), isNot(contains(3022)));
    });
  });

  test('instantané du jeu de données : même index que l\'archive complète', () {
    final all = readScrutinsArchive(
      fixtureArchive(
        numeros: [
          ...fixtureNumeros,
          ...articleUniqueNumeros,
          3022, // amendement, écarté de l'instantané
          2372, // sous-amendement
        ],
      ),
    );
    final dossiers = DossierIndex.fromArchive(fixtureDossiersArchive());
    final snapshot = ConfirmedSnapshot.fromJson(
      jsonDecode(jsonEncode(ConfirmedSnapshot.fromDump(all).toJson())),
    );
    expect(snapshot.lastNumero, 7349);
    expect(snapshot.scrutins.map((s) => s.numero), isNot(contains(3022)));
    expect(
      encode(
        reconcile(
          confirmed: snapshot.scrutins,
          confirmedUpTo: snapshot.lastNumero,
          generatedAt: generatedAt,
          dossiers: dossiers,
        ).index,
      ),
      encode(
        buildDecisionIndex(all, generatedAt: generatedAt, dossiers: dossiers),
      ),
    );
  });
}
