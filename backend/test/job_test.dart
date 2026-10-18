import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

import 'fixtures.dart';

/// Source simulée : sert l'archive des fixtures avec un `Last-Modified` donné
/// et respecte `If-Modified-Since` comme le serveur de l'Assemblée.
class FakeDumpSource implements DumpSource {
  FakeDumpSource(this.lastModified, {List<int> Function()? archive})
    : _archive = archive ?? fixtureArchive;

  String lastModified;
  final List<int> Function() _archive;
  final requests = <String?>[];

  /// Simule une panne du serveur.
  bool failing = false;

  @override
  Future<DumpFetch> fetch({String? ifModifiedSince}) async {
    requests.add(ifModifiedSince);
    if (failing) throw const HttpException('HTTP 503');
    if (ifModifiedSince == lastModified) return const DumpNotModified();
    return DumpDownloaded(_archive(), lastModified: lastModified);
  }
}

FakeDumpSource fakeDossiers(String lastModified) =>
    FakeDumpSource(lastModified, archive: fixtureDossiersArchive);

void main() {
  late Directory dir;
  late LocalDirectoryStore store;
  final clock = DateTime.utc(2026, 10, 17, 10, 17);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vote_job_test');
    store = LocalDirectoryStore(dir.path);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<DecisionIndex> readIndex() async =>
      DecisionIndex.fromJson(jsonDecode((await store.read(indexPath))!));

  test('publie les décisions, de la plus récente à la plus ancienne', () async {
    final outcome = await runJob(
      source: FakeDumpSource('Sat, 17 Oct 2026 10:30:00 GMT'),
      store: store,
      clock: () => clock,
    );

    expect(outcome, isA<JobPublished>());
    final index = await readIndex();
    expect(index.generatedAt, clock);
    expect(index.decisions.map((d) => d.numero), [
      7349, // l'article unique d'une proposition de résolution, 2026-06-04
      6346, // l'ensemble (CMP)
      5731, // motion de censure, 2026-02-25
      4802, // déclaration du Gouvernement, 2025-12-17
      4758, // l'ensemble (lecture définitive)
      4696, // l'ensemble (nouvelle lecture)
      4241, // rejet de la première partie du PLF 2026, 2025-11-21
      3054, // déclaration de politique générale, 2025-09-08
      2900, // l'ensemble, 2025-07-02
      2873, // motion de rejet préalable adoptée, 2025-06-30
      2633, // l'article unique (vaut vote sur l'ensemble), 2025-06-23
      2278, // l’ensemble, 2025-06-10
      1194, // l'ensemble, 2025-04-01
      1018, // l'ensemble d'une proposition de résolution, 2025-03-13
      519, // motion de censure, 2024-12-04
      504, // l'ensemble (deuxième lecture)
      289, // l'ensemble (CMP)
      217, // l'ensemble, 2024-10-31
    ]);
    final censure = index.decisions.firstWhere((d) => d.numero == 519);
    expect(censure.id, 'VTANR5L17V519');
    expect(censure.type, DecisionType.motionDeCensure);
    expect(censure.result, VoteResult.adopte);
    expect(censure.status, DecisionStatus.confirmee);
    expect(censure.date, DateTime.utc(2024, 12, 4));
    final rejet = index.decisions.firstWhere((d) => d.numero == 2873);
    expect(rejet.type, DecisionType.rejetPrealable);
    expect(
      rejet.result,
      VoteResult.rejete,
      reason: 'motion adoptée = texte rejeté',
    );
    expect(
      censure.sourceUrl,
      'https://www.assemblee-nationale.fr/dyn/17/scrutins/519',
    );
  });

  test(
    'chaque scrutin public porte son décompte dans l\'index (#29)',
    () async {
      await runJob(
        source: FakeDumpSource('Sat, 17 Oct 2026 10:30:00 GMT'),
        store: store,
        clock: () => clock,
      );
      final json = jsonDecode((await store.read(indexPath))!) as Map;
      final decisions = (json['decisions'] as List).cast<Map>();
      expect(decisions, everyElement(containsPair('count', isA<Map>())));
      final index = await readIndex();
      final narcotrafic = index.decisions.firstWhere((d) => d.numero == 1194);
      expect(
        narcotrafic.count,
        const VoteTally(pour: 436, contre: 75, abstentions: 39),
      );
      // Même décompte que le fichier de détail, sans les non-votants.
      final detail = DecisionDetail.fromJson(
        jsonDecode((await store.read(decisionDetailPath(narcotrafic.id)))!),
      );
      expect(detail.count!.tally, narcotrafic.count);
    },
  );

  test('le fichier publié porte la version du schéma', () async {
    await runJob(
      source: FakeDumpSource('Sat, 17 Oct 2026 10:30:00 GMT'),
      store: store,
      clock: () => clock,
    );
    final json = jsonDecode((await store.read(indexPath))!) as Map;
    expect(json['schemaVersion'], schemaVersion);
    expect(indexPath, 'v1/latest.json');
  });

  test('ne retraite rien si le jeu de données n\'a pas changé', () async {
    final source = FakeDumpSource('Sat, 17 Oct 2026 10:30:00 GMT');
    await runJob(source: source, store: store, clock: () => clock);
    final published = await store.read(indexPath);

    final second = await runJob(
      source: source,
      store: store,
      clock: () => clock.add(const Duration(hours: 1)),
    );

    expect(second, isA<JobSkipped>());
    expect(source.requests, [null, 'Sat, 17 Oct 2026 10:30:00 GMT']);
    expect(await store.read(indexPath), published);
  });

  test('retraite le jeu de données quand il a changé', () async {
    final source = FakeDumpSource('Fri, 16 Oct 2026 10:30:00 GMT');
    await runJob(source: source, store: store, clock: () => clock);

    source.lastModified = 'Sat, 17 Oct 2026 10:30:00 GMT';
    final later = clock.add(const Duration(days: 1));
    final outcome = await runJob(
      source: source,
      store: store,
      clock: () => later,
    );

    expect(outcome, isA<JobPublished>());
    expect((await readIndex()).generatedAt, later);
  });

  test('--force retraite même si rien n\'a changé', () async {
    final source = FakeDumpSource('Sat, 17 Oct 2026 10:30:00 GMT');
    await runJob(source: source, store: store, clock: () => clock);
    final outcome = await runJob(
      source: source,
      store: store,
      clock: () => clock,
      force: true,
    );
    expect(outcome, isA<JobPublished>());
    expect(source.requests.last, isNull);
  });

  group('dossiers législatifs', () {
    const scrutinsDate = 'Sat, 17 Oct 2026 10:30:00 GMT';
    const dossiersDate = 'Sat, 17 Oct 2026 13:16:27 GMT';

    Future<DecisionSummary> published(int numero) async =>
        (await readIndex()).decisions.firstWhere((d) => d.numero == numero);

    test('enrichit les décisions avec le titre court et l\'étape', () async {
      await runJob(
        source: FakeDumpSource(scrutinsDate),
        dossiers: fakeDossiers(dossiersDate),
        store: store,
        clock: () => clock,
      );
      final d = await published(1194);
      expect(d.shortTitle, 'Sortir la France du piège du narcotrafic');
      expect(d.stage, "1re lecture à l'AN");
      expect(
        d.dossierUrl,
        'https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N50169',
      );
    });

    test('publie les textes adoptés à main levée', () async {
      final outcome = await runJob(
        source: FakeDumpSource(scrutinsDate),
        dossiers: fakeDossiers(dossiersDate),
        store: store,
        clock: () => clock,
      );
      final json = jsonDecode((await store.read(indexPath))!) as Map;
      final convention = (json['decisions'] as List).cast<Map>().firstWhere(
        (d) => d['id'] == 'L17-VD234087DEC',
      );
      expect(convention['voteMode'], 'main_levee');
      expect(convention.containsKey('numero'), isFalse);
      expect(convention['result'], 'adopte');
      expect(
        convention.containsKey('count'),
        isFalse,
        reason: 'pas de décompte',
      );
      expect(
        (await readIndex()).decisions
            .where((d) => d.voteMode == VoteMode.mainLevee)
            .map((d) => d.id),
        ['L17-VD234087DEC', 'L17-VD230548DEC', 'L17-VD224512DEC'],
      );
      expect(outcome.toString(), contains('3 adoptées à main levée'));
    });

    test('ne retélécharge les dossiers que s\'ils ont changé', () async {
      final scrutins = FakeDumpSource(scrutinsDate);
      final dossiers = fakeDossiers(dossiersDate);
      Future<JobOutcome> run() => runJob(
        source: scrutins,
        dossiers: dossiers,
        store: store,
        clock: () => clock,
      );
      await run();

      // Rien n'a changé : requêtes conditionnelles, rien de republié.
      expect(await run(), isA<JobSkipped>());
      expect(dossiers.requests, [null, dossiersDate]);
      expect(scrutins.requests, [null, scrutinsDate]);

      // Seuls les scrutins changent : l'index des dossiers en cache sert.
      scrutins.lastModified = 'Sun, 18 Oct 2026 10:30:00 GMT';
      expect(await run(), isA<JobPublished>());
      expect(dossiers.requests.last, dossiersDate);
      expect(
        (await published(1194)).shortTitle,
        'Sortir la France du piège du narcotrafic',
      );
    });

    test(
      'de nouveaux dossiers font retraiter les scrutins inchangés',
      () async {
        final scrutins = FakeDumpSource(scrutinsDate);
        final dossiers = fakeDossiers(dossiersDate);
        Future<JobOutcome> run() => runJob(
          source: scrutins,
          dossiers: dossiers,
          store: store,
          clock: () => clock,
        );
        await run();

        dossiers.lastModified = 'Sun, 18 Oct 2026 13:16:27 GMT';
        expect(await run(), isA<JobPublished>());
        expect(scrutins.requests.last, isNull);
        final state = jsonDecode((await store.read(dossiersStateKey))!) as Map;
        expect(state['lastModified'], 'Sun, 18 Oct 2026 13:16:27 GMT');
      },
    );

    test('publie quand même si les dossiers sont indisponibles', () async {
      final dossiers = fakeDossiers(dossiersDate)..failing = true;
      final outcome = await runJob(
        source: FakeDumpSource(scrutinsDate),
        dossiers: dossiers,
        store: store,
        clock: () => clock,
      );
      expect(outcome, isA<JobPublished>());
      expect((outcome as JobPublished).warnings, hasLength(1));
      final d = await published(1194);
      expect(
        d.shortTitle,
        'Proposition de loi visant à sortir la France du piège du narcotrafic',
      );
      expect(d.stage, "1re lecture à l'AN");
      expect(await store.read(dossiersStateKey), isNull);
    });
  });

  test('l\'index contient au plus 50 décisions, les plus récentes', () {
    final scrutins = [
      for (var i = 1; i <= 80; i++)
        Scrutin(
          uid: 'VTANR5L17V$i',
          numero: i,
          // Deux scrutins par jour : le numéro départage les égalités.
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

    final index = buildDecisionIndex(scrutins..shuffle(), generatedAt: clock);

    expect(index.decisions, hasLength(maxIndexDecisions));
    expect(index.decisions.map((d) => d.numero), [
      for (var i = 80; i > 30; i--) i,
    ]);
  });
}
