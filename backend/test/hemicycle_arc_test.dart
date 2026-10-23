import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

import 'decision_details_test.dart'
    show RecordingStore, fixture, organesArchive;
import 'fixtures.dart';
import 'job_test.dart' show FakeDumpSource, fakeDossiers;
import 'live_pass_test.dart' show FakeSite;
import 'site_reader_test.dart' show sitePage;

/// Arc du vote dans l'ordre de l'hémicycle (#67), sur des scrutins et des
/// acteurs réels (`test/fixtures/organes/acteur/` : un député par groupe).
void main() {
  final groups = GroupDirectory.fromArchive(organesArchive());

  HemicycleSegment pour(int n) => HemicycleSegment(ArcPosition.pour, n);
  HemicycleSegment abst(int n) => HemicycleSegment(ArcPosition.abstention, n);
  HemicycleSegment contre(int n) => HemicycleSegment(ArcPosition.contre, n);

  /// Groupes de [numero], de gauche à droite.
  List<String> leftToRight(int numero, GroupDirectory? directory) =>
      [for (final g in fixture(numero).groupVotes) g.organeRef]..sort(
        (a, b) => groupPlace(b, directory).compareTo(groupPlace(a, directory)),
      );

  group('place des groupes (acteurs réels)', () {
    test('place moyenne des sièges des membres actuels', () {
      expect(groups['PO845413']!.place, 595, reason: 'LFI-NFP');
      expect(groups['PO845401']!.place, 76, reason: 'RN');
      expect(groups['PO840056']!.place, 322, reason: 'non-inscrits');
      // Deux membres : sièges 99 et 104.
      expect(groups['PO872880']!.place, 101.5, reason: 'UDR');
    });

    test('groupe dissous : sièges actuels de ses anciens membres', () {
      // Leurs deux anciens membres siègent aujourd'hui à l'UDR (99 et 104).
      expect(groups['PO847173']!.place, 101.5, reason: "UDR, jusqu'en 2025");
      expect(groups['PO845520']!.place, 101.5, reason: 'À Droite, 2024');
    });

    test('acteur illisible ou sans siège : ignoré', () {
      expect(parseActeurSeat('{"acteur": {}}'), isNull);
      expect(parseActeurSeat('pas du JSON'), isNull);
    });

    test('se relit depuis son cache, places comprises', () {
      final reread = GroupDirectory.fromJson(
        jsonDecode(jsonEncode(groups.toJson())),
      );
      expect(reread['PO845413']!.place, 595);
      expect(jsonEncode(reread.toJson()), jsonEncode(groups.toJson()));
    });

    test('un annuaire en cache sans place (version 1) est reconstruit', () {
      expect(
        () => GroupDirectory.fromJson({
          'version': 1,
          'groups': {
            'PO845401': {'name': 'Rassemblement National'},
          },
        }),
        throwsFormatException,
      );
    });

    test('ordre de gauche à droite de la 17e législature', () {
      expect(
        [
          for (final ref in leftToRight(8706, groups))
            groups[ref]!.abbreviation,
        ],
        [
          'LFI-NFP', 'GDR', 'EcoS', 'SOC', 'LIOT', 'Dem', 'NI', 'EPR', //
          'HOR', 'DR', 'UDR', 'RN',
        ],
      );
    });

    test('sans place connue : table de repli par sigle, non-inscrits et '
        'groupe inconnu à droite', () {
      final withoutPlaces = GroupDirectory({
        for (final ref in leftToRight(8706, groups))
          ref: PoliticalGroup(
            uid: ref,
            name: groups[ref]!.name,
            abbreviation: groups[ref]!.abbreviation,
          ),
      });
      expect(
        [
          for (final ref in leftToRight(8706, withoutPlaces))
            withoutPlaces[ref]!.abbreviation,
        ],
        [
          'LFI-NFP', 'GDR', 'EcoS', 'SOC', 'LIOT', 'Dem', 'EPR', 'HOR', //
          'DR', 'UDR', 'RN', 'NI',
        ],
      );
      expect(groupPlace('PO0', withoutPlaces), 0);
      expect(groupPlace('PO845401', null), 0);
    });
  });

  group('arc (scrutins réels)', () {
    test('8706 : abstention de LFI-NFP tout à gauche, le reste pour', () {
      // LFI-NFP : 66 abstentions, puis ses 4 voix pour, collées à celles des
      // autres groupes ; une abstention UDR près de la droite.
      expect(hemicycleArc(fixture(8706).groupVotes, groups), [
        abst(66),
        pour(382),
        abst(1),
        pour(121),
      ]);
    });

    test('8610 (rejeté) : la gauche et le centre contre, la droite pour', () {
      expect(hemicycleArc(fixture(8610).groupVotes, groups), [
        contre(187),
        pour(151),
      ]);
    });

    test('8611 (rejeté) : un groupe partagé est découpé dans le sens de ses '
        'voisins', () {
      // DR : 1 contre, 5 abstentions, 9 pour, entre Horizons (contre) et
      // l'UDR (pour).
      expect(hemicycleArc(fixture(8611).groupVotes, groups), [
        contre(199),
        abst(5),
        pour(144),
      ]);
    });

    test('voix exprimées des groupes, sans les non-votants ; pas deux '
        'tronçons voisins de même sens', () {
      for (final numero in [8610, 8611, 8706, 6346, 7349]) {
        final s = fixture(numero);
        final arc = hemicycleArc(s.groupVotes, groups)!;
        int sum(ArcPosition p) => arc
            .where((a) => a.position == p)
            .fold(0, (total, a) => total + a.n);
        int groupSum(int Function(Decompte) of) =>
            s.groupVotes.fold(0, (total, g) => total + of(g.decompte));
        expect(sum(ArcPosition.pour), groupSum((d) => d.pour));
        expect(sum(ArcPosition.abstention), groupSum((d) => d.abstentions));
        expect(sum(ArcPosition.contre), groupSum((d) => d.contre));
        for (var i = 1; i < arc.length; i++) {
          expect(arc[i].position, isNot(arc[i - 1].position));
        }
      }
    });

    test("sans vote par groupe (scrutin lu sur le site) : pas d'arc", () {
      expect(hemicycleArc(const [], groups), isNull);
    });

    test("dans l'index : avec les arcs donnés, sinon sans arc", () {
      final scrutins = [fixture(8706), fixture(8610)];
      final index = buildDecisionIndex(
        scrutins,
        generatedAt: DateTime.utc(2026, 10, 23),
        arcs: hemicycleArcs(scrutins, groups),
      );
      final byId = {for (final d in index.decisions) d.id: d};
      expect(byId['VTANR5L17V8706']!.arc, hasLength(4));
      expect(byId['VTANR5L17V8610']!.arc, [contre(187), pour(151)]);
      expect(
        buildDecisionIndex(
          scrutins,
          generatedAt: DateTime.utc(2026, 10, 23),
        ).decisions.map((d) => d.arc),
        everyElement(isNull),
      );
    });
  });

  group('publication', () {
    late Directory dir;
    late RecordingStore store;
    final now = DateTime.utc(2026, 10, 20, 15);

    setUp(() {
      dir = Directory.systemTemp.createTempSync('hemicycle_arc_test');
      store = RecordingStore(dir.path);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('index, détail et instantané : arc publié, gardé par le passage en '
        'direct', () async {
      await runJob(
        source: FakeDumpSource(
          'Mon, 19 Oct 2026 10:25:00 GMT',
          archive: () =>
              fixtureArchive(numeros: [...fixtureNumeros, 8705, 8706]),
        ),
        dossiers: fakeDossiers('Sat, 17 Oct 2026 04:00:00 GMT'),
        organes: FakeDumpSource(
          'Sat, 17 Oct 2026 01:50:34 GMT',
          archive: organesArchive,
        ),
        store: store,
        clock: () => now,
      );
      final index = DecisionIndex.fromJson(
        jsonDecode((await store.read(indexPath))!),
      );
      final decision = index.decisions.firstWhere(
        (d) => d.id == 'VTANR5L17V8706',
      );
      expect(decision.arc, [abst(66), pour(382), abst(1), pour(121)]);
      final detail = DecisionDetail.fromJson(
        jsonDecode((await store.read(decisionDetailPath(decision.id)))!),
      );
      expect(detail.decision.arc, decision.arc);
      final snapshot = (await ConfirmedSnapshot.read(store, []))!;
      expect(snapshot.arcs['VTANR5L17V8706'], decision.arc);

      // Le passage en direct reconstruit l'index sans vote par groupe : il
      // reprend les arcs de l'instantané, l'index ne change pas.
      final before = await store.read(indexPath);
      store.writes.clear();
      await runLivePass(
        site: FakeSite(sitePage('liste_scrutins_solennels.html')),
        store: store,
        clock: () => now,
        pageDelay: Duration.zero,
      );
      expect(store.writes, isNot(contains(indexPath)));
      expect(await store.read(indexPath), before);
    });
  });
}
