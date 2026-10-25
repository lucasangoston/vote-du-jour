import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

import 'agenda_test.dart' show FakeAgendaSource;
import 'fixtures.dart';
import 'job_test.dart' show FakeDumpSource;
import 'live_pass_test.dart' show FakeSite;
import 'site_reader_test.dart' show sitePage;
import 'summary_test.dart' show FakeLlm, FakeTexts, dossiersWithPlfss;

const _plfss = 'DLR5L17N54951';
const _plf = 'DLR5L17N54629';

/// Votes sur les articles des fixtures du ticket #55, comme les garde le
/// job.
List<ArticleVote> _votes() => [
  for (final n in inDebateNumeros)
    ?ArticleVote.fromScrutin(
      parseScrutinJson(fixtureFile(n).readAsStringSync()),
    ),
];

/// Articles du bloc : (numéro, sort, scrutin).
List<(String, ArticleOutcome, String)> _articles(InDebate? d) => [
  for (final a in d!.articles) (a.number, a.outcome, a.scrutinRef),
];

Scrutin _scrutin(int numero, String titre, VoteResult result, {String? day}) =>
    Scrutin(
      uid: 'VTANR5L17V$numero',
      numero: numero,
      date: DateTime.parse('${day ?? '2026-10-19'}T00:00:00Z'),
      titre: titre,
      codeTypeVote: 'SPO',
      libelleTypeVote: 'scrutin public ordinaire',
      result: result,
      decompte: const Decompte(
        pour: 0,
        contre: 0,
        abstentions: 0,
        nonVotants: 0,
      ),
      dossierRef: null,
      groupVotes: const [],
    );

void main() {
  group('articleVoteOf (intitulés réels)', () {
    const adopte = VoteResult.adopte;
    const rejete = VoteResult.rejete;

    test('vote sur un article : adopté ou rejeté, numéro tel qu\'écrit', () {
      expect(
        articleVoteOf(
          "l'article 38 (examen prioritaire) du projet de loi de finances "
          'pour 2027 (première lecture).',
          adopte,
        ),
        (number: '38', outcome: ArticleOutcome.adopte),
      );
      expect(
        articleVoteOf(
          "l’article 40 (examen prioritaire) du projet de loi de finances "
          'pour 2027 (première lecture).',
          rejete,
        ),
        (number: '40', outcome: ArticleOutcome.rejete),
      );
      for (final (titre, number) in [
        (
          "l'article liminaire du projet de loi de finances pour 2025",
          'liminaire',
        ),
        ("l'article premier de la proposition de loi visant à", 'premier'),
        ("l'article 9 bis de la proposition de loi portant", '9 bis'),
        ("l'article 8 bis A du projet de loi relatif à", '8 bis A'),
        ("l'article 1er AA de la proposition de loi relative à", '1er AA'),
        (
          "l'article 27 terdecies (examen prioritaire) du projet",
          '27 terdecies',
        ),
        ("l'article 48 et État A du projet de loi de finances", '48'),
        ("l'article 25 A de la proposition de loi portant", '25 A'),
      ]) {
        expect(articleVoteOf(titre, adopte)?.number, number, reason: titre);
      }
    });

    test('amendement de suppression adopté : article supprimé', () {
      expect(
        articleVoteOf(
          "l'amendement n° 30 de M. Daubié et les amendements identiques "
          "suivants de suppression de l'article 5 du projet de loi de "
          'financement de la sécurité sociale pour 2027 (première lecture).',
          adopte,
        ),
        (number: '5', outcome: ArticleOutcome.supprime),
      );
      expect(
        articleVoteOf(
          "l'amendement de suppression n° 789 de M. Clouet à l'article 2 du "
          'projet de loi de financement de la sécurité sociale pour 2026 '
          '(première lecture).',
          adopte,
        ),
        (number: '2', outcome: ArticleOutcome.supprime),
      );
    });

    test('autres scrutins : rien', () {
      for (final (titre, result) in [
        // Suppression rejetée : l'article est voté ensuite.
        (
          "l'amendement n° 424 de M. Ray et les amendements identiques "
              "suivants de suppression de l'article 5 du projet de loi de "
              'finances pour 2027 (première lecture).',
          rejete,
        ),
        (
          "l'amendement n° 3089 de M. Juvin à l'article 5 du projet de loi de "
              'finances pour 2027 (première lecture).',
          adopte,
        ),
        (
          "l'amendement n° 1398 de M. Midy après l'article 4 du projet de loi "
              'de finances pour 2027 (première lecture).',
          adopte,
        ),
        (
          "le sous-amendement n° 12 à l'amendement n° 3 de suppression de "
              "l'article 2 du projet de loi",
          adopte,
        ),
        // L'article unique vaut vote sur l'ensemble : c'est une décision.
        ("l'article unique de la proposition de loi visant à", adopte),
        (
          "l'amendement n° 1 de M. Vicot de suppression de l'article unique "
              'de la proposition de loi visant à',
          adopte,
        ),
        (
          'la motion de rejet préalable, déposée par Mme Mathilde Panot, du '
              'projet de loi de financement de la sécurité sociale pour 2027 '
              '(première lecture).',
          rejete,
        ),
        (
          "l'ensemble du projet de loi de finances pour 2027 (première "
              'lecture).',
          adopte,
        ),
      ]) {
        expect(articleVoteOf(titre, result), isNull, reason: titre);
      }
    });

    test('fixtures : seuls les articles et les suppressions adoptées', () {
      expect(
        [for (final v in _votes()) (v.numero, v.number, v.outcome)],
        [
          (8876, '5', ArticleOutcome.adopte),
          (8883, '35', ArticleOutcome.supprime),
          (8887, '37', ArticleOutcome.supprime),
          (8888, '38', ArticleOutcome.adopte),
          (8889, '39', ArticleOutcome.supprime),
          (8892, '40', ArticleOutcome.rejete),
          (8896, 'liminaire', ArticleOutcome.supprime),
          (8897, 'premier', ArticleOutcome.supprime),
          (8905, '4', ArticleOutcome.adopte),
          (8931, '5', ArticleOutcome.supprime),
        ],
      );
      final v = _votes().firstWhere((v) => v.numero == 8888);
      expect(v.dossierRef, _plf);
      expect(v.seanceRef, 'RUANR5L17S2027IDS30951');
    });
  });

  group('buildInDebate (agenda et scrutins réels, 16-21/10/2026)', () {
    final points = readAgendaArchive(
      fixtureAgendaArchive(withPastSeances: true),
      since: DateTime.utc(2026, 10, 1),
    ).points;
    final votes = _votes();

    test('lundi 19/10 à 23 h : PLF, article 38 adopté, article 40 rejeté', () {
      final d = buildInDebate(
        points,
        now: DateTime.utc(2026, 10, 19, 21),
        votes: votes,
        confirmedUpTo: 8931,
      )!;
      expect(d.dossierRef, _plf);
      expect(d.dossierUrl, Dossier(uid: _plf, title: '').url);
      expect(
        d.shortTitle,
        'Projet de loi de finances pour 2027 (première partie)',
      );
      // Séance du soir en cours (21 h 30, heure de Paris).
      expect(d.seanceRef, 'RUANR5L17S2027IDS30951');
      expect(d.startsAt, DateTime.utc(2026, 10, 19, 19, 30));
      // Du plus récent au plus ancien ; article 36 : suppression rejetée,
      // pas de vote sur l'article ; amendement à l'article 5 ignoré ; les
      // votes du PLFSS (autre dossier) aussi.
      expect(_articles(d), [
        ('40', ArticleOutcome.rejete, 'VTANR5L17V8892'),
        ('39', ArticleOutcome.supprime, 'VTANR5L17V8889'),
        ('38', ArticleOutcome.adopte, 'VTANR5L17V8888'),
        ('37', ArticleOutcome.supprime, 'VTANR5L17V8887'),
        ('35', ArticleOutcome.supprime, 'VTANR5L17V8883'),
        ('5', ArticleOutcome.adopte, 'VTANR5L17V8876'),
      ]);
      expect(d.articles.first.date, DateTime.utc(2026, 10, 19));
    });

    test('mercredi 21/10 à 21 h 17 : PLFSS, séance de l\'après-midi', () {
      final d = buildInDebate(
        points,
        now: DateTime.utc(2026, 10, 21, 19, 17),
        votes: votes,
        confirmedUpTo: 8931,
        decisions: [
          DecisionSummary(
            id: 'VTANR5L17V9000',
            numero: 9000,
            type: DecisionType.ensembleTexte,
            status: DecisionStatus.confirmee,
            result: VoteResult.adopte,
            date: DateTime.utc(2026, 10, 1),
            officialTitle: '…',
            sourceUrl:
                'https://www.assemblee-nationale.fr/dyn/17/scrutins/9000',
            shortTitle: 'Budget de la Sécurité sociale 2027',
            dossierUrl: Dossier(uid: _plfss, title: '').url,
          ),
        ],
      )!;
      expect(d.dossierRef, _plfss);
      // La séance du soir (21 h 30) n'a pas commencé.
      expect(d.seanceRef, 'RUANR5L17S2027IDS30955');
      // Titre court : celui d'une décision publiée du même dossier.
      expect(d.shortTitle, 'Budget de la Sécurité sociale 2027');
      expect(_articles(d), [
        ('5', ArticleOutcome.supprime, 'VTANR5L17V8931'),
        ('4', ArticleOutcome.adopte, 'VTANR5L17V8905'),
        ('premier', ArticleOutcome.supprime, 'VTANR5L17V8897'),
        ('liminaire', ArticleOutcome.supprime, 'VTANR5L17V8896'),
      ]);
    });

    test('rien sans texte en débat dans les 7 derniers jours', () {
      // Avant les séances des fixtures, et plus de 7 jours après la
      // dernière (03/11).
      expect(
        buildInDebate(points, now: DateTime.utc(2026, 10, 10), votes: votes),
        isNull,
      );
      expect(
        buildInDebate(points, now: DateTime.utc(2026, 11, 11), votes: votes),
        isNull,
      );
      expect(
        buildInDebate(const [], now: DateTime.utc(2026, 10, 19, 21)),
        isNull,
      );
    });

    test('texte en débat sans article voté : liste vide', () {
      final d = buildInDebate(
        points,
        now: DateTime.utc(2026, 10, 19, 21),
        votes: const [],
      )!;
      expect(d.dossierRef, _plf);
      expect(d.articles, isEmpty);
    });

    test('un article voté deux fois : son dernier vote', () {
      final second = ArticleVote.fromScrutin(
        _scrutin(
          8893,
          "l'article 38 (examen prioritaire) du projet de loi de finances "
          'pour 2027 (première lecture).',
          VoteResult.rejete,
        ),
      )!;
      final d = buildInDebate(
        points,
        now: DateTime.utc(2026, 10, 19, 21),
        votes: [
          ...votes,
          ArticleVote(
            uid: second.uid,
            numero: second.numero,
            date: second.date,
            titre: second.titre,
            result: second.result,
            number: second.number,
            outcome: second.outcome,
            dossierRef: _plf,
            seanceRef: 'RUANR5L17S2027IDS30951',
          ),
        ],
        confirmedUpTo: 8931,
      )!;
      expect(_articles(d).take(2), [
        ('38', ArticleOutcome.rejete, 'VTANR5L17V8893'),
        ('40', ArticleOutcome.rejete, 'VTANR5L17V8892'),
      ]);
      expect(d.articles.where((a) => a.number == '38'), hasLength(1));
    });

    test('votes du site plus récents que le jeu de données : rattachés par '
        'le texte nommé, puis gardés du bloc publié', () {
      final now = DateTime.utc(2026, 10, 19, 21);
      // Le jeu de données s'arrête au scrutin 8888.
      final confirmed = [
        for (final v in votes)
          if (v.numero <= 8888) v,
      ];
      final site = [
        for (final n in [8889, 8891, 8892])
          ?ArticleVote.fromScrutin(
            parseScrutinJson(fixtureFile(n).readAsStringSync()).withoutDossier,
          ),
        // Autre texte : pas rattaché.
        ?ArticleVote.fromScrutin(
          _scrutin(
            8894,
            "l'article 2 de la proposition de loi visant à autre chose "
            '(première lecture).',
            VoteResult.adopte,
          ),
        ),
      ];
      final live = buildInDebate(
        points,
        now: now,
        votes: confirmed,
        confirmedUpTo: 8888,
        provisional: site,
      )!;
      expect(_articles(live).take(3), [
        ('40', ArticleOutcome.rejete, 'VTANR5L17V8892'),
        ('39', ArticleOutcome.supprime, 'VTANR5L17V8889'),
        ('38', ArticleOutcome.adopte, 'VTANR5L17V8888'),
      ]);

      // Passage horaire sans le site : les votes provisoires viennent du
      // bloc publié.
      final hourly = buildInDebate(
        points,
        now: now,
        votes: confirmed,
        confirmedUpTo: 8888,
        previous: live,
      );
      expect(jsonEncode(hourly!.toJson()), jsonEncode(live.toJson()));

      // Bloc publié d'un autre texte : ignoré.
      expect(
        buildInDebate(
          points,
          now: DateTime.utc(2026, 10, 21, 19, 17),
          votes: votes,
          confirmedUpTo: 8888,
          previous: live,
        )!.articles.map((a) => a.scrutinRef),
        isNot(contains('VTANR5L17V8892')),
      );
    });

    test('plusieurs textes dans la séance : celui du dernier article voté', () {
      AgendaPoint point(String id, String dossier, String label) => AgendaPoint(
        id: id,
        seanceRef: 'RUANR5L17S2027IDS30940',
        startsAt: DateTime.utc(2026, 10, 13, 13),
        endsAt: DateTime.utc(2026, 10, 13, 18, 25),
        kind: UpcomingKind.discussion,
        label: label,
        dossierRef: dossier,
      );
      final niche = [
        point('PT1', 'DLR5L17N1', 'Discussion de la proposition de loi A'),
        point('PT2', 'DLR5L17N2', 'Discussion de la proposition de loi B'),
      ];
      ArticleVote vote(int numero, String dossier) => ArticleVote(
        uid: 'VTANR5L17V$numero',
        numero: numero,
        date: DateTime.utc(2026, 10, 13),
        titre: "l'article 1er de la proposition de loi (première lecture).",
        result: VoteResult.adopte,
        number: '1er',
        outcome: ArticleOutcome.adopte,
        dossierRef: dossier,
        seanceRef: 'RUANR5L17S2027IDS30940',
      );
      final now = DateTime.utc(2026, 10, 13, 17);
      expect(buildInDebate(niche, now: now)!.dossierRef, 'DLR5L17N1');
      expect(
        buildInDebate(
          niche,
          now: now,
          votes: [vote(1, 'DLR5L17N1'), vote(2, 'DLR5L17N2')],
          confirmedUpTo: 2,
        )!.dossierRef,
        'DLR5L17N2',
      );
    });
  });

  group('passages', () {
    late Directory dir;
    late LocalDirectoryStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('vote_job_in_debate');
      store = LocalDirectoryStore(dir.path);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<DecisionIndex> readIndex() async =>
        DecisionIndex.fromJson(jsonDecode((await store.read(indexPath))!));

    Future<void> publishDump(List<int> numeros, DateTime now) async {
      final outcome = await runJob(
        source: FakeDumpSource(
          'dump ${numeros.last}',
          archive: () =>
              fixtureArchive(numeros: [...fixtureNumeros, ...numeros]),
        ),
        store: store,
        clock: () => now,
      );
      expect(outcome, isA<JobPublished>());
    }

    Future<AgendaReport> agendaPass(DateTime now) => runAgendaPass(
      store: store,
      source: FakeAgendaSource(
        '"a"',
        archive: () => fixtureAgendaArchive(withPastSeances: true),
      ),
      clock: () => now,
    );

    test('le job garde les votes sur les articles, le passage de l\'agenda '
        'publie le bloc', () async {
      final now = DateTime.utc(2026, 10, 21, 19, 17);
      await publishDump(inDebateNumeros, now);
      final state = await ArticleVotesState.read(store, []);
      expect(state!.lastNumero, 8931);
      expect(state.votes, hasLength(10));

      final report = await agendaPass(now);
      expect(report.written, isTrue);
      expect(report.toString(), contains('En débat : Projet de loi de '));
      final index = await readIndex();
      expect(index.inDebate!.dossierRef, _plfss);
      expect(index.inDebate!.articles.map((a) => a.number), [
        '5',
        '4',
        'premier',
        'liminaire',
      ]);

      // Le job republie l'index en gardant le bloc.
      await runJob(
        source: FakeDumpSource('autre', archive: fixtureArchive),
        store: store,
        clock: () => now,
        force: true,
      );
      expect((await readIndex()).inDebate?.dossierRef, _plfss);

      // Plus de 7 jours après la dernière séance : plus rien.
      await agendaPass(DateTime.utc(2026, 11, 11));
      expect((await readIndex()).inDebate, isNull);
    });

    test('le PLFSS en débat porte un résumé dans latest.json (#73), gardé '
        'par les passages suivants sans nouvel appel', () async {
      final now = DateTime.utc(2026, 10, 21, 19, 17);
      await publishDump(inDebateNumeros, now);
      await agendaPass(now);
      expect((await readIndex()).inDebate!.dossierRef, _plfss);

      final llm = FakeLlm();
      final texts = FakeTexts();
      Future<SummaryReport> summaryPass() => runSummaryPass(
        store: store,
        service: SummaryService(llm: llm, texts: texts),
        dossiers: DossierIndex.fromArchive(dossiersWithPlfss()),
        clock: () => now,
      );
      // Appels sur le PLFSS (les décisions publiées sont résumées aussi).
      int plfssCalls() => [
        for (var i = 0; i < llm.requests.length; i++)
          if (llm.userMessage(i).contains('taxe soda')) i,
      ].length;
      final report = await summaryPass();
      expect(report.summarized.first, inDebateSummaryId(_plfss));
      expect(plfssCalls(), 1);
      expect((await readIndex()).inDebate!.summary!.title, 'Titre lisible');

      // Passage de l'agenda, détection en direct, job : le bloc est
      // recalculé et garde son résumé, tiré du cache.
      await agendaPass(now.add(const Duration(minutes: 5)));
      expect((await readIndex()).inDebate!.summary!.points, hasLength(3));
      await runLivePass(
        site: FakeSite(sitePage('liste_scrutins.html')),
        store: store,
        clock: () => now.add(const Duration(minutes: 10)),
      );
      expect((await readIndex()).inDebate!.summary, isNotNull);
      await runJob(
        source: FakeDumpSource('autre', archive: fixtureArchive),
        store: store,
        clock: () => now,
        force: true,
      );
      expect((await readIndex()).inDebate!.summary, isNotNull);

      // Second passage du résumeur : pas de nouvel appel sur le PLFSS.
      await summaryPass();
      expect(plfssCalls(), 1);
      expect((await readIndex()).inDebate!.summary, isNotNull);
    });

    test('détection en direct : article lu sur le site, puis confirmé par '
        'le jeu de données', () async {
      // Vendredi 16/10 à 23 h, séance du soir sur le PLF : le jeu de
      // données s'arrête au scrutin 8875, le site va jusqu'au 8877.
      final now = DateTime.utc(2026, 10, 16, 21);
      await publishDump([8874, 8875], now);
      await agendaPass(now);
      expect((await readIndex()).inDebate!.articles, isEmpty);

      final outcome = await runLivePass(
        site: FakeSite(sitePage('liste_scrutins.html')),
        store: store,
        clock: () => now,
      );
      expect(outcome, isA<LiveChecked>());
      expect((outcome as LiveChecked).published, isTrue);
      var d = (await readIndex()).inDebate!;
      expect(d.dossierRef, _plf);
      expect(_articles(d), [('5', ArticleOutcome.adopte, 'VTANR5L17V8876')]);

      // Passage horaire sans nouveau jeu de données : l'article reste.
      await agendaPass(now.add(const Duration(minutes: 30)));
      d = (await readIndex()).inDebate!;
      expect(_articles(d), [('5', ArticleOutcome.adopte, 'VTANR5L17V8876')]);

      // Le jeu de données le confirme.
      await publishDump([8874, 8875, 8876], now);
      await agendaPass(now.add(const Duration(hours: 1)));
      expect(_articles((await readIndex()).inDebate), [
        ('5', ArticleOutcome.adopte, 'VTANR5L17V8876'),
      ]);
    });
  });
}

extension on Scrutin {
  /// Le scrutin tel que le donne le site : sans dossier ni séance.
  Scrutin get withoutDossier => Scrutin(
    uid: uid,
    numero: numero,
    date: date,
    titre: titre,
    codeTypeVote: '',
    libelleTypeVote: '',
    result: result,
    decompte: decompte,
    dossierRef: null,
    groupVotes: const [],
  );
}
