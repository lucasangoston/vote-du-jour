import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

import 'fixtures.dart';

/// Source simulée : sert l'archive des fixtures avec un `Last-Modified` donné
/// et respecte `If-Modified-Since` comme le serveur de l'Assemblée.
class FakeDumpSource implements DumpSource {
  FakeDumpSource(this.lastModified);

  String lastModified;
  final requests = <String?>[];

  @override
  Future<DumpFetch> fetch({String? ifModifiedSince}) async {
    requests.add(ifModifiedSince);
    if (ifModifiedSince == lastModified) return const DumpNotModified();
    return DumpDownloaded(fixtureArchive(), lastModified: lastModified);
  }
}

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
      5731, // motion de censure, 2026-02-25
      4802, // déclaration du Gouvernement, 2025-12-17
      4241, // rejet de la première partie du PLF 2026, 2025-11-21
      3054, // déclaration de politique générale, 2025-09-08
      2873, // motion de rejet préalable adoptée, 2025-06-30
      2278, // l’ensemble, 2025-06-10
      1018, // l'ensemble d'une proposition de résolution, 2025-03-13
      519, // motion de censure, 2024-12-04
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
