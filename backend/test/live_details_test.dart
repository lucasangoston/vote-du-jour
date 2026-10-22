import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

import 'decision_details_test.dart' show RecordingStore, organesArchive;
import 'fixtures.dart';
import 'job_test.dart' show FakeDumpSource, fakeDossiers;
import 'live_pass_test.dart' show FakeSite;
import 'site_reader_test.dart' show sitePage;

/// Fichiers de détail des décisions provisoires (détection en direct, #10).
void main() {
  late Directory dir;
  late RecordingStore store;
  // Mardi 20 octobre 2026, 17 h à Paris.
  final now = DateTime.utc(2026, 10, 20, 15);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('live_details_test');
    store = RecordingStore(dir.path);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<JobOutcome> publishDump(
    String lastModified, {
    List<int> extra = const [],
  }) => runJob(
    source: FakeDumpSource(
      lastModified,
      archive: () => fixtureArchive(numeros: [...fixtureNumeros, ...extra]),
    ),
    dossiers: fakeDossiers('Sat, 17 Oct 2026 04:00:00 GMT'),
    organes: FakeDumpSource(
      'Sat, 17 Oct 2026 01:50:34 GMT',
      archive: organesArchive,
    ),
    store: store,
    clock: () => now,
  );

  Future<DecisionDetail?> detail(String id) async {
    final raw = await store.read(decisionDetailPath(id));
    return raw == null ? null : DecisionDetail.fromJson(jsonDecode(raw));
  }

  test('provisoire : décompte du site, sans vote par groupe, puis complété '
      'par le jeu de données', () async {
    await publishDump('Mon, 19 Oct 2026 10:25:00 GMT');
    final confirmedBefore = await store.read(
      decisionDetailPath('VTANR5L17V6346'),
    );
    store.writes.clear();

    final site = FakeSite(sitePage('liste_scrutins_solennels.html'));
    await runLivePass(
      site: site,
      store: store,
      clock: () => now,
      pageDelay: Duration.zero,
    );

    final provisional = (await detail('VTANR5L17V8706'))!;
    expect(provisional.decision.status, DecisionStatus.provisoire);
    expect(provisional.count, isNotNull);
    expect(provisional.count!.pour, greaterThan(0));
    expect(provisional.groups, isEmpty);
    // Les détails des décisions confirmées ne sont pas touchés.
    expect(store.writes.where((k) => k.startsWith('v1/decisions/')).toSet(), {
      decisionDetailPath('VTANR5L17V8705'),
      decisionDetailPath('VTANR5L17V8706'),
    });
    expect(
      await store.read(decisionDetailPath('VTANR5L17V6346')),
      confirmedBefore,
    );
    // Détails écrits avant l'index qui renvoie vers eux.
    expect(
      store.writes.indexOf(indexPath),
      greaterThan(store.writes.indexOf(decisionDetailPath('VTANR5L17V8706'))),
    );

    // Passage suivant, rien de nouveau : aucun détail réécrit.
    store.writes.clear();
    await runLivePass(
      site: site,
      store: store,
      clock: () => now.add(const Duration(minutes: 10)),
      pageDelay: Duration.zero,
    );
    expect(store.writes.where((k) => k.startsWith('v1/decisions/')), isEmpty);

    // Le jeu de données du lendemain : confirmée, avec le vote par groupe.
    await publishDump('Wed, 21 Oct 2026 10:25:00 GMT', extra: [8705, 8706]);
    final confirmed = (await detail('VTANR5L17V8706'))!;
    expect(confirmed.decision.status, DecisionStatus.confirmee);
    expect(confirmed.groups, isNotEmpty);
    expect(confirmed.groups.first.name, 'Rassemblement National');
  });

  test('le passage en direct garde les résumés du cache, sans appel ni '
      'écriture du cache (#9)', () async {
    await publishDump('Mon, 19 Oct 2026 10:25:00 GMT');
    const summary = PlainSummary(
      title: 'Titre résumé',
      explanation: 'Phrase.',
      points: ['Un.', 'Deux.', 'Trois.'],
      promptVersion: 1,
    );
    final cache = SummaryCache()
      ..['VTANR5L17V6346'] = SummaryEntry(
        status: SummaryStatus.resume,
        updatedAt: now,
        summary: summary,
        source: SourceKind.expose,
      );
    await cache.write(store);
    store.writes.clear();

    final site = FakeSite(sitePage('liste_scrutins_solennels.html'));
    await runLivePass(
      site: site,
      store: store,
      clock: () => now,
      pageDelay: Duration.zero,
    );

    final index = DecisionIndex.fromJson(
      jsonDecode((await store.read(indexPath))!),
    );
    expect(
      index.decisions.firstWhere((d) => d.id == 'VTANR5L17V6346').summary,
      const PlainSummary(
        title: 'Titre résumé',
        explanation: 'Phrase.',
        promptVersion: 1,
      ),
    );
    expect(store.writes, isNot(contains(summaryCacheKey)));
  });
}
