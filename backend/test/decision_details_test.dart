import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

import 'fixtures.dart';
import 'job_test.dart' show FakeDumpSource;

/// Les organes de `test/fixtures/organes/`, réunis dans une archive au format
/// du jeu de données officiel (`json/organe/<uid>.json`).
List<int> organesArchive() {
  final archive = Archive();
  final files =
      Directory(
          'test/fixtures/organes/organe',
        ).listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    archive.addFile(
      ArchiveFile.bytes(
        'json/organe/${f.uri.pathSegments.last}',
        f.readAsBytesSync(),
      ),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

Scrutin fixture(int numero) =>
    parseScrutinJson(fixtureFile(numero).readAsStringSync());

/// Store local qui compte les écritures, par clé.
class RecordingStore extends LocalDirectoryStore {
  RecordingStore(super.root);

  final writes = <String>[];

  @override
  Future<void> write(
    String key,
    String body, {
    String contentType = 'application/json; charset=utf-8',
    String? cacheControl,
  }) {
    writes.add(key);
    return super.write(
      key,
      body,
      contentType: contentType,
      cacheControl: cacheControl,
    );
  }
}

void main() {
  final clock = DateTime.utc(2026, 10, 17, 10, 17);
  final groups = GroupDirectory.fromArchive(organesArchive());

  group('annuaire des groupes (organes réels)', () {
    test('garde les groupes politiques, y compris dissous ou renommés', () {
      expect(groups.length, 14);
      expect(groups['PO59047'], isNull, reason: 'commission, pas un groupe');
      expect(groups['PO845401']?.name, 'Rassemblement National');
      expect(groups['PO845401']?.abbreviation, 'RN');
      expect(groups['PO845439']?.name, 'Écologiste et Social');
      expect(groups['PO845439']?.abbreviation, 'EcoS');
      // Groupe renommé : l'ancien organe reste cité par les anciens scrutins.
      expect(groups['PO847173']?.name, 'UDR');
      expect(groups['PO872880']?.name, 'Union des droites pour la République');
      expect(groups['PO872880']?.abbreviation, 'UDR');
      expect(groups['PO840056']?.name, 'Non inscrit');
    });

    test('se relit depuis son cache', () {
      final reread = GroupDirectory.fromJson(
        jsonDecode(jsonEncode(groups.toJson())),
      );
      expect(jsonEncode(reread.toJson()), jsonEncode(groups.toJson()));
      expect(reread['PO845413']?.abbreviation, 'LFI-NFP');
    });
  });

  group('fichier de détail (scrutins réels)', () {
    DecisionDetail detailOf(int numero, {GroupDirectory? directory}) {
      final scrutin = fixture(numero);
      final index = buildDecisionIndex([scrutin], generatedAt: clock);
      return buildDecisionDetails(
        [scrutin],
        index,
        groups: directory ?? groups,
      ).single;
    }

    test('décompte et vote par groupe d\'un texte de CMP (6346)', () {
      final detail = detailOf(6346);
      expect(detail.decision.id, 'VTANR5L17V6346');
      expect(detail.decision.type, DecisionType.ensembleTexte);
      expect(detail.decision.result, VoteResult.adopte);
      expect(
        detail.count,
        const VoteCount(pour: 141, contre: 0, abstentions: 12, nonVotants: 2),
      );
      expect(detail.groups, hasLength(12));

      final rn = detail.groups.first;
      expect(rn.organeRef, 'PO845401');
      expect(rn.name, 'Rassemblement National');
      expect(rn.abbreviation, 'RN');
      expect(rn.position, GroupPosition.pour);
      expect(
        rn.count,
        const VoteCount(pour: 30, contre: 0, abstentions: 0, nonVotants: 0),
      );

      final dr = detail.groups.firstWhere((g) => g.organeRef == 'PO845425');
      expect(dr.name, 'Droite Républicaine');
      expect(dr.position, GroupPosition.abstention, reason: '5 pour, 6 abst.');
      final udr = detail.groups.firstWhere((g) => g.organeRef == 'PO872880');
      expect(udr.name, 'Union des droites pour la République');
      expect(udr.position, GroupPosition.abstention);

      // La somme des groupes redonne le décompte du scrutin.
      int sum(int Function(VoteCount) f) =>
          detail.groups.map((g) => f(g.count)).reduce((a, b) => a + b);
      expect(sum((c) => c.pour), 141);
      expect(sum((c) => c.abstentions), 12);
    });

    test(
      'motion de censure (519) : un groupe sans votant n\'est pas « pour »',
      () {
        final detail = detailOf(519);
        expect(detail.decision.type, DecisionType.motionDeCensure);
        expect(detail.count?.pour, 331);
        final epr = detail.groups.firstWhere((g) => g.organeRef == 'PO845407');
        expect(epr.name, 'Ensemble pour la République');
        // L'open data donne `positionMajoritaire: pour` avec zéro voix.
        expect(epr.count.votants, 0);
        expect(epr.position, GroupPosition.nonVotant);
        final udr = detail.groups.firstWhere((g) => g.organeRef == 'PO847173');
        expect(udr.name, 'UDR');
        expect(udr.position, GroupPosition.pour);
      },
    );

    test('sans annuaire, les groupes gardent leur référence', () {
      final scrutin = fixture(1194);
      final index = buildDecisionIndex([scrutin], generatedAt: clock);
      final detail = buildDecisionDetails([scrutin], index).single;
      expect(detail.groups.first.organeRef, 'PO845401');
      expect(detail.groups.first.name, unknownGroupName);
      expect(detail.groups.first.abbreviation, isNull);
    });

    test('une décision sans scrutin n\'a ni décompte ni groupes', () {
      final summary = buildDecisionIndex([
        fixture(1194),
      ], generatedAt: clock).decisions.single;
      final detail = buildDecisionDetail(summary);
      expect(detail.count, isNull);
      expect(detail.groups, isEmpty);
      expect(detail.toJson().containsKey('count'), isFalse);
    });
  });

  group('contrat du fichier de détail', () {
    test('aller-retour JSON', () {
      final scrutin = fixture(1194);
      final index = buildDecisionIndex(
        [scrutin],
        generatedAt: clock,
        dossiers: DossierIndex.fromArchive(fixtureDossiersArchive()),
      );
      // L'index contient aussi les textes adoptés à main levée des dossiers.
      final detail = buildDecisionDetails(
        [scrutin],
        index,
        groups: groups,
      ).firstWhere((d) => d.decision.id == 'VTANR5L17V1194');

      final encoded = encodeDecisionDetail(detail);
      final reread = DecisionDetail.fromJson(jsonDecode(encoded));

      expect(encodeDecisionDetail(reread), encoded);
      expect(
        reread.decision.shortTitle,
        'Sortir la France du piège du narcotrafic',
      );
      expect(reread.decision.stage, "1re lecture à l'AN");
      expect(
        reread.decision.dossierUrl,
        'https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N50169',
      );
      expect(reread.count, detail.count);
      expect(
        reread.groups.map((g) => g.name),
        detail.groups.map((g) => g.name),
      );
      expect(reread.groups.map((g) => g.position), [
        for (final g in detail.groups) g.position,
      ]);
      expect(
        decisionDetailPath('VTANR5L17V1194'),
        'v1/decisions/VTANR5L17V1194.json',
      );
    });
  });

  group('publication par le job', () {
    late Directory dir;
    late RecordingStore store;
    const scrutinsDate = 'Sat, 17 Oct 2026 10:30:00 GMT';
    const organesDate = 'Sat, 17 Oct 2026 01:50:34 GMT';

    setUp(() {
      dir = Directory.systemTemp.createTempSync('vote_job_details');
      store = RecordingStore(dir.path);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    FakeDumpSource organes(String lastModified) =>
        FakeDumpSource(lastModified, archive: organesArchive);

    test('publie un fichier de détail par décision de l\'index', () async {
      final outcome = await runJob(
        source: FakeDumpSource(scrutinsDate),
        organes: organes(organesDate),
        store: store,
        clock: () => clock,
      );

      expect(outcome, isA<JobPublished>());
      final index = DecisionIndex.fromJson(
        jsonDecode((await store.read(indexPath))!),
      );
      for (final d in index.decisions) {
        final raw = await store.read(decisionDetailPath(d.id));
        expect(raw, isNotNull, reason: d.id);
        final detail = DecisionDetail.fromJson(jsonDecode(raw!));
        expect(detail.decision.toJson(), d.toJson());
        expect(detail.groups, isNotEmpty);
        expect(
          detail.groups.map((g) => g.name),
          isNot(contains(unknownGroupName)),
        );
      }
      expect((outcome as JobPublished).detailsWritten, index.decisions.length);
      // Les détails sont écrits avant l'index qui renvoie vers eux.
      expect(
        store.writes.indexOf(indexPath),
        greaterThan(
          store.writes.lastIndexOf(decisionDetailPath(index.decisions.last.id)),
        ),
      );
      final state = jsonDecode((await store.read(organesStateKey))!) as Map;
      expect(state['lastModified'], organesDate);
    });

    test('ne réécrit que les fichiers qui ont changé', () async {
      final scrutins = FakeDumpSource(scrutinsDate);
      await runJob(
        source: scrutins,
        organes: organes(organesDate),
        store: store,
        clock: () => clock,
      );
      store.writes.clear();

      // Nouveau jeu de données, mêmes scrutins : seuls l'index et l'état
      // changent.
      scrutins.lastModified = 'Sun, 18 Oct 2026 10:30:00 GMT';
      final outcome = await runJob(
        source: scrutins,
        organes: organes(organesDate),
        store: store,
        clock: () => clock.add(const Duration(days: 1)),
      );

      expect((outcome as JobPublished).detailsWritten, 0);
      expect(store.writes.where((k) => k.startsWith('v1/decisions/')), isEmpty);
      expect(store.writes, contains(indexPath));
    });

    test(
      'des organes régénérés sans changement ne font rien republier',
      () async {
        final scrutins = FakeDumpSource(scrutinsDate);
        await runJob(
          source: scrutins,
          organes: organes(organesDate),
          store: store,
          clock: () => clock,
        );
        store.writes.clear();

        const nextNight = 'Sun, 18 Oct 2026 01:50:34 GMT';
        final outcome = await runJob(
          source: scrutins,
          organes: organes(nextNight),
          store: store,
          clock: () => clock,
        );

        expect(outcome, isA<JobSkipped>());
        expect(store.writes, [organesStateKey]);
        final state = jsonDecode((await store.read(organesStateKey))!) as Map;
        expect(state['lastModified'], nextNight);
      },
    );

    test('main levée : détail sans décompte ni groupes', () async {
      await runJob(
        source: FakeDumpSource(scrutinsDate),
        dossiers: FakeDumpSource(
          'Sat, 17 Oct 2026 13:16:27 GMT',
          archive: fixtureDossiersArchive,
        ),
        organes: organes(organesDate),
        store: store,
        clock: () => clock,
      );
      final index = DecisionIndex.fromJson(
        jsonDecode((await store.read(indexPath))!),
      );
      final mainLevee = index.decisions
          .where((d) => d.voteMode == VoteMode.mainLevee)
          .toList();
      expect(mainLevee, isNotEmpty);
      for (final d in mainLevee) {
        final detail = DecisionDetail.fromJson(
          jsonDecode((await store.read(decisionDetailPath(d.id)))!),
        );
        expect(detail.decision.toJson(), d.toJson());
        expect(detail.decision.numero, isNull);
        expect(detail.count, isNull);
        expect(detail.groups, isEmpty);
      }
    });

    test(
      'organes indisponibles : publie quand même, groupes non nommés',
      () async {
        final outcome = await runJob(
          source: FakeDumpSource(scrutinsDate),
          organes: organes(organesDate)..failing = true,
          store: store,
          clock: () => clock,
        );
        expect(outcome, isA<JobPublished>());
        expect((outcome as JobPublished).warnings, hasLength(1));
        final detail = DecisionDetail.fromJson(
          jsonDecode((await store.read(decisionDetailPath('VTANR5L17V6346')))!),
        );
        expect(detail.groups.first.name, unknownGroupName);
        expect(await store.read(organesStateKey), isNull);
      },
    );
  });
}
