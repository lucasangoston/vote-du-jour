import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

import 'fixtures.dart';
import 'job_test.dart' show FakeDumpSource;

/// Agenda simulé : sert une archive avec un `ETag` donné et respecte
/// `If-None-Match` comme le CDN de l'Assemblée.
class FakeAgendaSource implements AgendaSource {
  FakeAgendaSource(this.etag, {List<int> Function()? archive})
    : archive = archive ?? fixtureAgendaArchive;

  String etag;
  List<int> Function() archive;
  final requests = <String?>[];

  /// Simule une panne du serveur.
  bool failing = false;

  @override
  Future<AgendaFetch> fetch({String? ifNoneMatch}) async {
    requests.add(ifNoneMatch);
    if (failing) throw const HttpException('HTTP 503');
    if (ifNoneMatch == etag) return const AgendaNotModified();
    return AgendaDownloaded(archive(), etag: etag);
  }
}

const _plfss = 'DLR5L17N54951';
const _plf = 'DLR5L17N54629';
String _dossierUrl(String uid) =>
    'https://www.assemblee-nationale.fr/dyn/17/dossiers/$uid';

/// La réunion [uid] des fixtures, avec le point [point] passé à
/// « Supprimé » (report par la Conférence des présidents).
String _withDeletedPoint(String uid, String point) {
  final json = jsonDecode(fixtureReunion(uid)) as Map<String, Object?>;
  final reunion = json['reunion'] as Map<String, Object?>;
  final points =
      ((reunion['ODJ'] as Map)['pointsODJ'] as Map)['pointODJ'] as List;
  for (final p in points.cast<Map<String, Object?>>()) {
    if (p['uid'] == point) (p['cycleDeVie'] as Map)['etat'] = 'Supprimé';
  }
  return jsonEncode(json);
}

void main() {
  // Mercredi 21 octobre 2026, 21 h 17 à Paris : date de l'agenda des
  // fixtures, pendant la séance du soir sur le PLFSS.
  final now = DateTime.utc(2026, 10, 21, 19, 17);

  group('readAgendaArchive (agenda réel du 21/10/2026)', () {
    final points = readAgendaArchive(fixtureAgendaArchive(), since: now).points;

    test('séances de l\'Assemblée seulement, points confirmés', () {
      expect(points.map((p) => p.id), [
        'RUANR5L17S2027IDS30954PT53278', // 21/10 soir, suite PLFSS
        'RUANR5L17S2027IDS31030PT53428', // 24/10, suite PLFSS
        'RUANR5L17S2027IDS30963PT53286', // 26/10 soir, suite PLFSS
        'RUANR5L17S2027IDS30964PT53289', // 27/10, vote solennel PLFSS
        'RUANR5L17S2027IDS30964PT53435', // 27/10, suite PLF (1re partie)
        'RUANR5L17S2027IDS30977PT53449', // 03/11, vote solennel PLF
        'RUANR5L17S2027IDS30977PT53450', // 03/11, discussion PLF (2e partie)
      ]);
      // Ni Sénat (RUSN…), ni commission (…IDC…), ni séance supprimée
      // (31036), ni point supprimé (suite de la 2e partie le 27/10).
      expect(points.every((p) => p.seanceRef.startsWith('RUAN')), isTrue);
      expect(points.any((p) => p.seanceRef.contains('IDC')), isFalse);
      expect(points.any((p) => p.seanceRef.endsWith('31036')), isFalse);
    });

    test('dossier d\'un vote solennel retrouvé par le texte nommé', () {
      final votes = points.where((p) => p.kind == UpcomingKind.voteSolennel);
      expect(votes.map((p) => (p.startsAt, p.dossierRef)), [
        // 27/10 à 15 h et 03/11 à 15 h, heure de Paris (UTC+1).
        (DateTime.utc(2026, 10, 27, 14), _plfss),
        (DateTime.utc(2026, 11, 3, 14), _plf),
      ]);
      // Suite de la discussion sans dossier dans l'agenda (24/10).
      expect(points[1].dossierRef, _plfss);
      expect(points[1].followUp, isTrue);
    });

    test('une séance finie n\'est plus retenue', () {
      final later = readAgendaArchive(
        fixtureAgendaArchive(),
        since: DateTime.utc(2026, 10, 27, 23),
      ).points;
      expect(later.first.seanceRef, 'RUANR5L17S2027IDS30977');
    });
  });

  group('buildUpcoming', () {
    final points = readAgendaArchive(
      fixtureAgendaArchive(),
      since: now.subtract(const Duration(days: 1)),
    ).points;

    test('discussions sur 7 jours, votes solennels sur 14, un point par '
        'texte', () {
      final items = buildUpcoming(points, now: now);
      expect(
        items.map(
          (u) => (u.kind, u.startsAt, u.inProgress, u.dossierRef, u.shortTitle),
        ),
        [
          (
            UpcomingKind.discussion,
            DateTime.utc(2026, 10, 21, 19, 30),
            true,
            _plfss,
            'Projet de loi de financement de la sécurité sociale pour 2027',
          ),
          (
            UpcomingKind.voteSolennel,
            DateTime.utc(2026, 10, 27, 14),
            false,
            _plfss,
            'Projet de loi de financement de la sécurité sociale pour 2027',
          ),
          (
            UpcomingKind.discussion,
            DateTime.utc(2026, 10, 27, 14),
            true,
            _plf,
            'Projet de loi de finances pour 2027 (première partie)',
          ),
          (
            UpcomingKind.voteSolennel,
            DateTime.utc(2026, 11, 3, 14),
            false,
            _plf,
            'Projet de loi de finances pour 2027 (première partie)',
          ),
        ],
      );
      final vote = items[1];
      expect(vote.id, 'RUANR5L17S2027IDS30964PT53289');
      expect(vote.seanceRef, 'RUANR5L17S2027IDS30964');
      expect(
        vote.label,
        'Vote solennel sur le projet de loi de financement de la sécurité '
        'sociale pour 2027',
      );
      expect(vote.dossierUrl, _dossierUrl(_plfss));
    });

    test('titre court d\'une décision publiée du même dossier', () {
      DecisionSummary decision(String dossier, String title) => DecisionSummary(
        id: 'VTANR5L17V9000',
        numero: 9000,
        type: DecisionType.ensembleTexte,
        status: DecisionStatus.confirmee,
        result: VoteResult.rejete,
        date: DateTime.utc(2026, 10, 1),
        officialTitle: '…',
        sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/9000',
        shortTitle: title,
        dossierUrl: _dossierUrl(dossier),
      );
      final items = buildUpcoming(
        points,
        now: now,
        decisions: [
          decision(_plfss, 'Budget de la Sécurité sociale 2027'),
          decision(_plf, 'Budget de l\'État 2027'),
        ],
      );
      expect(items.map((u) => u.shortTitle), [
        'Budget de la Sécurité sociale 2027',
        'Budget de la Sécurité sociale 2027',
        'Budget de l\'État 2027',
        // La précision du libellé reste sur le titre d'un vote.
        'Budget de l\'État 2027 (première partie)',
      ]);
    });

    test('séances du Sénat ignorées, point supprimé ignoré', () {
      // Lundi 19 octobre, 7 h à Paris : le Sénat siège à 9 h (dossiers
      // cités dans l'agenda), le vote solennel sur le PLF du mardi 20 est
      // supprimé.
      final monday = DateTime.utc(2026, 10, 19, 5);
      final items = buildUpcoming(
        readAgendaArchive(fixtureAgendaArchive(), since: monday).points,
        now: monday,
      );
      expect(items.map((u) => (u.seanceRef, u.kind, u.inProgress)), [
        ('RUANR5L17S2027IDS30952', UpcomingKind.discussion, false),
        ('RUANR5L17S2027IDS30964', UpcomingKind.voteSolennel, false),
      ]);
    });

    test('libellé nettoyé sans dossier', () {
      expect(
        cleanLabel(
          'Vote solennel sur le projet de loi de finances pour 2027 '
          '(première partie).',
        ),
        'Projet de loi de finances pour 2027 (première partie)',
      );
      expect(
        cleanLabel('Discussion de la proposition de loi visant à X'),
        'Proposition de loi visant à X',
      );
      expect(
        cleanLabel('Suite de la discussion de l’ensemble du texte'),
        'Ensemble du texte',
      );
    });
  });

  group('runAgendaPass', () {
    late Directory dir;
    late LocalDirectoryStore store;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('vote_job_agenda');
      store = LocalDirectoryStore(dir.path);
      await runJob(
        source: FakeDumpSource('Wed, 21 Oct 2026 10:30:00 GMT'),
        store: store,
        clock: () => now,
      );
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<DecisionIndex> readIndex() async =>
        DecisionIndex.fromJson(jsonDecode((await store.read(indexPath))!));

    test(
      'publie le bloc, puis ne retélécharge que si l\'agenda change',
      () async {
        final source = FakeAgendaSource('"a"');
        final before = await readIndex();
        expect(before.upcoming, isNull);

        var report = await runAgendaPass(
          store: store,
          source: source,
          clock: () => now,
        );
        expect(report.downloaded, isTrue);
        expect(report.written, isTrue);
        var index = await readIndex();
        expect(index.upcoming, hasLength(4));
        expect(
          index.decisions.map((d) => d.id),
          before.decisions.map((d) => d.id),
        );
        expect(index.generatedAt, before.generatedAt);

        // Même agenda : requête conditionnelle, rien à réécrire.
        report = await runAgendaPass(
          store: store,
          source: source,
          clock: () => now,
        );
        expect(source.requests, [null, '"a"']);
        expect(report.downloaded, isFalse);
        expect(report.written, isFalse);

        // Le lendemain soir, sans nouvel agenda : la fenêtre avance.
        report = await runAgendaPass(
          store: store,
          source: source,
          clock: () => now.add(const Duration(days: 1)),
        );
        expect(report.downloaded, isFalse);
        expect(report.written, isTrue);
        index = await readIndex();
        expect(
          index.upcoming!.first.seanceRef,
          'RUANR5L17S2027IDS31030', // la séance du 22/10 n'est pas en fixture
        );
      },
    );

    test(
      'un point passé à « Supprimé » disparaît au passage suivant',
      () async {
        final source = FakeAgendaSource('"a"');
        await runAgendaPass(store: store, source: source, clock: () => now);
        expect(
          (await readIndex()).upcoming!.map((u) => u.id),
          contains('RUANR5L17S2027IDS30964PT53289'),
        );

        source
          ..etag = '"b"'
          ..archive = () => fixtureAgendaArchive(
            replace: {
              'RUANR5L17S2027IDS30964': _withDeletedPoint(
                'RUANR5L17S2027IDS30964',
                'RUANR5L17S2027IDS30964PT53289',
              ),
            },
          );
        final report = await runAgendaPass(
          store: store,
          source: source,
          clock: () => now,
        );
        expect(report.downloaded, isTrue);
        final upcoming = (await readIndex()).upcoming!;
        expect(
          upcoming.map((u) => u.id),
          isNot(contains('RUANR5L17S2027IDS30964PT53289')),
        );
        expect(upcoming.where((u) => u.kind == UpcomingKind.voteSolennel), [
          isA<UpcomingItem>().having((u) => u.dossierRef, 'dossierRef', _plf),
        ]);
      },
    );

    test('agenda en panne : avertissement, dernier agenda connu', () async {
      final source = FakeAgendaSource('"a"');
      await runAgendaPass(store: store, source: source, clock: () => now);
      final before = (await readIndex()).upcoming;

      source.failing = true;
      final report = await runAgendaPass(
        store: store,
        source: source,
        clock: () => now,
      );
      expect(report.warnings.single, contains('dernier agenda connu'));
      expect(_encode((await readIndex()).upcoming), _encode(before));
    });

    test('agenda en panne au premier passage : index intact', () async {
      final raw = await store.read(indexPath);
      final report = await runAgendaPass(
        store: store,
        source: FakeAgendaSource('"a"')..failing = true,
        clock: () => now,
      );
      expect(report.warnings.single, contains('agenda indisponible'));
      expect(await store.read(indexPath), raw);
      expect(await store.read(agendaStateKey), isNull);
    });

    test('le job republie l\'index en gardant le bloc', () async {
      await runAgendaPass(
        store: store,
        source: FakeAgendaSource('"a"'),
        clock: () => now,
      );
      final outcome = await runJob(
        source: FakeDumpSource('Thu, 22 Oct 2026 10:30:00 GMT'),
        store: store,
        clock: () => now,
      );
      expect(outcome, isA<JobPublished>());
      expect((await readIndex()).upcoming, hasLength(4));
    });
  });

  group('HttpAgendaSource', () {
    HttpAgendaSource source(MockClient client) => HttpAgendaSource(
      url: 'https://example.test/Agenda.json.zip',
      client: client,
      retryDelay: Duration.zero,
    );

    test('requête conditionnelle par ETag', () async {
      final headers = <String?>[];
      final client = MockClient((request) async {
        headers.add(request.headers['if-none-match']);
        return request.headers['if-none-match'] == '"x"'
            ? http.Response('', 304)
            : http.Response.bytes([1], 200, headers: {'etag': '"x"'});
      });
      final first = await source(client).fetch();
      expect(first, isA<AgendaDownloaded>());
      expect((first as AgendaDownloaded).etag, '"x"');
      expect(
        await source(client).fetch(ifNoneMatch: '"x"'),
        isA<AgendaNotModified>(),
      );
      expect(headers, [null, '"x"']);
    });

    test('retente après une réponse 503, pas après une 404', () async {
      var calls = 0;
      var client = MockClient((request) async {
        calls++;
        return calls == 1 ? http.Response('', 503) : http.Response('', 304);
      });
      expect(await source(client).fetch(), isA<AgendaNotModified>());
      expect(calls, 2);

      calls = 0;
      client = MockClient((request) async {
        calls++;
        return http.Response('', 404);
      });
      await expectLater(source(client).fetch(), throwsA(isA<HttpException>()));
      expect(calls, 1);
    });
  });
}

String _encode(List<UpcomingItem>? items) =>
    jsonEncode(items?.map((u) => u.toJson()).toList());
