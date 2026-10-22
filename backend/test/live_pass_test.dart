import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

import 'fixtures.dart';
import 'job_test.dart' show FakeDumpSource, fakeDossiers;
import 'site_reader_test.dart' show sitePage;

/// Site simulé : sert une page de liste (la page 1, et les suivantes de
/// [nextLists] ; à défaut, la même) et, éventuellement, des pages de
/// scrutin ; compte les requêtes.
class FakeSite implements SiteSource {
  FakeSite(this.list, {this.pages = const {}, this.nextLists});

  String list;
  final Map<int, String> pages;

  /// Pages 2, 3… de la liste ; `null` : toutes identiques à [list].
  final List<String>? nextLists;
  final scrutinRequests = <int>[];
  final listPagesRequested = <int>[];
  int get listRequests => listPagesRequested.length;

  @override
  Future<String> fetchList({int page = 1}) async {
    listPagesRequested.add(page);
    if (page == 1 || nextLists == null) return list;
    if (page - 2 < nextLists!.length) return nextLists![page - 2];
    throw HttpException('HTTP 503 (page $page)');
  }

  @override
  Future<String> fetchScrutin(int numero) async {
    scrutinRequests.add(numero);
    return pages[numero] ?? (throw HttpException('HTTP 404 ($numero)'));
  }
}

void main() {
  late Directory dir;
  late LocalDirectoryStore store;
  // Mardi 20 octobre 2026, 17 h à Paris.
  final now = DateTime.utc(2026, 10, 20, 15);
  // Pauses entre les pages de la liste (aucune attente réelle).
  final pauses = <Duration>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('live_pass_test');
    store = LocalDirectoryStore(dir.path);
    pauses.clear();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<DecisionIndex> readIndex() async =>
      DecisionIndex.fromJson(jsonDecode((await store.read(indexPath))!));

  /// Publication du jeu de données (archive des fixtures, plus [extra]).
  Future<JobOutcome> publishDump(
    String lastModified, {
    List<int> extra = const [],
  }) => runJob(
    source: FakeDumpSource(
      lastModified,
      archive: () => fixtureArchive(numeros: [...fixtureNumeros, ...extra]),
    ),
    dossiers: fakeDossiers('Sat, 17 Oct 2026 04:00:00 GMT'),
    store: store,
    clock: () => now,
  );

  Future<LiveOutcome> pass(FakeSite site, {DateTime? at}) => runLivePass(
    site: site,
    store: store,
    clock: () => at ?? now,
    sleep: (d) async => pauses.add(d),
  );

  /// État de la détection où [lastSeen] est le dernier scrutin vu.
  Future<void> seen(int lastSeen) =>
      LiveState(lastSeenNumero: lastSeen, checkedAt: now).write(store);

  List<(int?, DecisionStatus)> top(DecisionIndex index, int n) => [
    for (final d in index.decisions.take(n)) (d.numero, d.status),
  ];

  test(
    'sans instantané du jeu de données : rien n\'est lu ni publié',
    () async {
      final site = FakeSite(sitePage('liste_scrutins_solennels.html'));
      final outcome = await pass(site);
      expect(outcome, isA<LiveSkipped>());
      expect(site.listRequests, 0);
      expect(await store.read(indexPath), isNull);
    },
  );

  test('provisoire, puis confirmée par le jeu de données', () async {
    await publishDump('Mon, 19 Oct 2026 10:25:00 GMT');
    expect(await store.read(confirmedSnapshotKey), isNotNull);

    // Pendant la séance : 8705 et 8706 apparaissent sur le site, juste après
    // le dernier scrutin vu.
    await seen(8704);
    final site = FakeSite(sitePage('liste_scrutins_solennels.html'));
    final outcome = await pass(site) as LiveChecked;
    expect(site.listRequests, 1);
    expect(site.scrutinRequests, isEmpty, reason: 'la liste suffit');
    expect(outcome.detected.map((s) => s.numero), [8705, 8706]);
    expect(outcome.published, isTrue);
    var index = await readIndex();
    expect(top(index, 2), [
      (8706, DecisionStatus.provisoire),
      (8705, DecisionStatus.provisoire),
    ]);
    expect(index.decisions.skip(2).map((d) => d.status).toSet(), {
      DecisionStatus.confirmee,
    });
    expect(index.generatedAt, now);
    final state = LiveState.fromJson(
      jsonDecode((await store.read(liveStateKey))!),
    );
    expect(state.provisional.map((p) => p.numero), [8705, 8706]);
    expect(state.provisional.first.detectedAt, now);

    // Passage suivant, rien de nouveau : l'index n'est pas réécrit.
    final again =
        await pass(site, at: now.add(const Duration(minutes: 10)))
            as LiveChecked;
    expect(again.detected, isEmpty);
    expect(again.published, isFalse);
    expect((await readIndex()).generatedAt, now);

    // Le jeu de données du lendemain les contient : confirmées.
    await publishDump('Wed, 21 Oct 2026 10:25:00 GMT', extra: [8705, 8706]);
    index = await readIndex();
    expect(top(index, 2), [
      (8706, DecisionStatus.confirmee),
      (8705, DecisionStatus.confirmee),
    ]);
    expect(
      LiveState.fromJson(
        jsonDecode((await store.read(liveStateKey))!),
      ).provisional,
      isEmpty,
    );
  });

  test(
    'une provisoire absente du nouveau jeu de données reste publiée',
    () async {
      await publishDump('Mon, 19 Oct 2026 10:25:00 GMT');
      await pass(FakeSite(sitePage('liste_scrutins_solennels.html')));

      // Le jeu de données s'arrête à 8705.
      await publishDump('Wed, 21 Oct 2026 10:25:00 GMT', extra: [8705]);
      expect(top(await readIndex(), 2), [
        (8706, DecisionStatus.provisoire),
        (8705, DecisionStatus.confirmee),
      ]);
    },
  );

  test(
    'site illisible : erreur journalisée, index et état inchangés',
    () async {
      await publishDump('Mon, 19 Oct 2026 10:25:00 GMT');
      await pass(FakeSite(sitePage('liste_scrutins_solennels.html')));
      final index = await store.read(indexPath);
      final state = await store.read(liveStateKey);

      final outcome = await pass(FakeSite('<html>maintenance</html>'));
      expect(outcome, isA<LiveFailed>());
      expect((outcome as LiveFailed).error, isA<FormatException>());
      expect(await store.read(indexPath), index);
      expect(await store.read(liveStateKey), state);

      // Le jeu de données se publie toujours, avec les provisoires connues.
      expect(
        await publishDump('Wed, 21 Oct 2026 10:25:00 GMT'),
        isA<JobPublished>(),
      );
      expect(
        (await readIndex()).decisions.first.status,
        DecisionStatus.provisoire,
      );
    },
  );

  group('pagination de la liste', () {
    Future<LiveState> readState() async =>
        LiveState.fromJson(jsonDecode((await store.read(liveStateKey))!));

    test('une page suffit : elle rejoint le dernier scrutin vu', () async {
      await publishDump('Mon, 19 Oct 2026 10:25:00 GMT');
      await seen(8850);
      final site = FakeSite(
        sitePage('liste_scrutins.html'),
        nextLists: const [],
      );
      final outcome = await pass(site) as LiveChecked;
      expect(site.listPagesRequested, [1]);
      expect(pauses, isEmpty);
      expect(outcome.listPages, 1);
      expect(outcome.warnings, isEmpty);
      expect((await readState()).lastSeenNumero, 8877);
    });

    test(
      'deux pages : la première ne contient que des scrutins non vus',
      () async {
        await publishDump('Mon, 19 Oct 2026 10:25:00 GMT');
        await seen(8704);
        // Page 1 : 50 amendements (8828 à 8877), tous postérieurs au dernier
        // scrutin vu ; page 2 (simulée) : 8705 et 8706, votes sur
        // l'ensemble.
        final site = FakeSite(
          sitePage('liste_scrutins.html'),
          nextLists: [sitePage('liste_scrutins_solennels.html')],
        );
        final outcome = await pass(site) as LiveChecked;
        expect(site.listPagesRequested, [1, 2]);
        expect(pauses, [listPageDelay]);
        expect(
          listPageDelay,
          greaterThanOrEqualTo(const Duration(seconds: 30)),
        );
        expect(outcome.listPages, 2);
        expect(outcome.listed, hasLength(52));
        expect(outcome.detected.map((s) => s.numero), [8705, 8706]);
        expect(outcome.published, isTrue);
        expect(outcome.warnings, isEmpty);
        expect((await readState()).lastSeenNumero, 8877);
      },
    );

    test('plafond atteint : les scrutins manquants sont signalés', () async {
      // Séance budgétaire, aucun passage depuis le jeu de données (n° 7349) :
      // la liste n'atteint jamais le dernier scrutin connu.
      await publishDump('Mon, 19 Oct 2026 10:25:00 GMT');
      final before = await store.read(indexPath);
      final site = FakeSite(sitePage('liste_scrutins.html'));
      final outcome = await pass(site) as LiveChecked;
      expect(site.listPagesRequested, [1, 2, 3, 4]);
      expect(pauses, hasLength(3));
      expect(outcome.listPages, maxListPagesPerPass);
      // Mêmes scrutins sur chaque page simulée : doublons écartés.
      expect(outcome.listed, hasLength(50));
      expect(outcome.newSinceDump, 50);
      expect(outcome.detected, isEmpty);
      expect(outcome.published, isFalse);
      expect(site.scrutinRequests, isEmpty);
      expect(await store.read(indexPath), before);
      expect(
        outcome.warnings.single,
        allOf(contains('7350 à 8827'), contains('4 pages')),
      );
      expect((await readState()).lastSeenNumero, 8877);
    });

    test('page suivante illisible : le trou est relu ensuite', () async {
      await publishDump('Mon, 19 Oct 2026 10:25:00 GMT');
      await seen(8704);
      final site = FakeSite(
        sitePage('liste_scrutins.html'),
        nextLists: const [],
      );
      final outcome = await pass(site) as LiveChecked;
      expect(site.listPagesRequested, [1, 2]);
      expect(outcome.warnings.single, contains('page 2 de la liste'));
      expect((await readState()).lastSeenNumero, 8704);
    });

    test('URL d\'une page de la liste', () {
      expect(
        siteListPageUrl(siteListUrl, 3),
        'https://www.assemblee-nationale.fr/dyn/17/scrutins?page=3&limit=50',
      );
      expect(
        siteListPageUrl('https://example.org/scrutins?limit=50', 2),
        'https://example.org/scrutins?limit=50&page=2',
      );
    });
  });

  test('sort absent de la liste : lu sur la page du scrutin', () async {
    await publishDump('Mon, 19 Oct 2026 10:25:00 GMT');
    final site = FakeSite(
      sitePage(
        'liste_scrutins_solennels.html',
      ).replaceAll('L&#039;Assemblée nationale a adopté', ''),
      pages: {8706: sitePage('scrutin_8706.html')},
    );
    final outcome = await pass(site) as LiveChecked;
    expect(site.scrutinRequests, unorderedEquals([8705, 8706]));
    // 8706 complété par sa page ; la page de 8705 est indisponible.
    expect(outcome.detected.map((s) => s.numero), [8706]);
    expect(outcome.detected.single.result, VoteResult.adopte);
    expect(outcome.warnings.last, contains('page du scrutin 8705'));
  });

  group('plages de détection (heure de Paris)', () {
    const window = LiveWindow();

    test('par défaut : en semaine, de 9 h à minuit', () {
      // Heure d'été (UTC+2).
      expect(window.contains(DateTime.utc(2026, 10, 20, 6, 59)), isFalse);
      expect(window.contains(DateTime.utc(2026, 10, 20, 7)), isTrue);
      expect(window.contains(DateTime.utc(2026, 10, 20, 21, 59)), isTrue);
      expect(window.contains(DateTime.utc(2026, 10, 20, 22)), isFalse);
      // Heure d'hiver (UTC+1), après le 25 octobre.
      expect(window.contains(DateTime.utc(2026, 10, 27, 7, 30)), isFalse);
      expect(window.contains(DateTime.utc(2026, 10, 27, 8)), isTrue);
      expect(window.contains(DateTime.utc(2026, 10, 27, 22, 50)), isTrue);
      // Samedi.
      expect(window.contains(DateTime.utc(2026, 10, 17, 12)), isFalse);
    });

    test('réglable', () {
      final w = LiveWindow.parse(days: '1-3,6', hours: '14-21');
      expect(w.days, {1, 2, 3, 6});
      expect((w.startHour, w.endHour), (14, 21));
      expect(w.contains(DateTime.utc(2026, 10, 17, 12)), isTrue); // sam. 14 h
      expect(
        () => LiveWindow.parse(days: '1-5', hours: '9'),
        throwsFormatException,
      );
      expect(
        () => LiveWindow.parse(days: '0-5', hours: '9-24'),
        throwsFormatException,
      );
    });
  });
}
