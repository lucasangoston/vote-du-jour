import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

import 'decision_details_test.dart' show fixture, organesArchive;
import 'fixtures.dart';
import 'job_test.dart' show FakeDumpSource;

/// Les organes de `test/fixtures/organes/organe/` et les 574 députés en
/// exercice de `test/fixtures/organes/hemicycle_acteurs.json`, au format du
/// jeu de données officiel. [abbreviations] remplace le sigle de groupes
/// (par référence d'organe), pour simuler un annuaire faux.
List<int> hemicycleArchive({Map<String, String> abbreviations = const {}}) {
  final archive = Archive();
  final organes =
      Directory(
          'test/fixtures/organes/organe',
        ).listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in organes) {
    final json = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
    final organe = json['organe'] as Map<String, Object?>;
    if (abbreviations[organe['uid']] case final abbreviation?) {
      organe['libelleAbrege'] = abbreviation;
    }
    archive.addFile(
      ArchiveFile.string(
        'json/organe/${f.uri.pathSegments.last}',
        jsonEncode(json),
      ),
    );
  }
  final acteurs =
      jsonDecode(
            File(
              'test/fixtures/organes/hemicycle_acteurs.json',
            ).readAsStringSync(),
          )
          as List;
  for (final a in acteurs) {
    final uid = ((a as Map)['acteur'] as Map)['uid']['#text'];
    archive.addFile(ArchiveFile.string('json/acteur/$uid.json', jsonEncode(a)));
  }
  return ZipEncoder().encodeBytes(archive);
}

/// Sièges du scrutin, de l'hémicycle « places réelles » (#71), sur des
/// scrutins et des acteurs réels.
void main() {
  final clock = DateTime.utc(2026, 10, 25, 10);
  final groups = GroupDirectory.fromArchive(hemicycleArchive());

  /// Nombre de sièges de [seats] qui ont voté [vote].
  int countOf(List<HemicycleSeat> seats, SeatVote vote) =>
      seats.where((s) => s.vote == vote).length;

  group('annuaire : places des députés et couleurs des groupes', () {
    test('place de chaque député en exercice', () {
      expect(groups.seats, hasLength(574));
      // PA1008 : SOC, siège 410.
      expect(groups.seats['PA1008'], (place: 410, group: 'PO845419'));
    });

    test('couleur officielle des groupes (couleurAssociee)', () {
      expect(groups['PO845401']!.color, '#313567', reason: 'RN');
      expect(groups['PO845413']!.color, '#C00D0D', reason: 'LFI-NFP');
    });

    test('se relit depuis son cache, places et couleurs comprises', () {
      final reread = GroupDirectory.fromJson(
        jsonDecode(jsonEncode(groups.toJson())),
      );
      expect(reread.seats, groups.seats);
      expect(reread['PO845401']!.color, '#313567');
      expect(jsonEncode(reread.toJson()), jsonEncode(groups.toJson()));
    });
  });

  group('vote nominatif (Scrutins.json)', () {
    test('place et vote de chaque votant, effectif du groupe', () {
      final rn = fixture(
        8706,
      ).groupVotes.firstWhere((g) => g.organeRef == 'PO845401');
      expect(rn.membres, 121);
      expect(rn.votants, hasLength(121));
      expect(
        rn.votants.first,
        isA<NominalVote>()
            .having((v) => v.acteurRef, 'acteurRef', 'PA793432')
            .having((v) => v.place, 'place', 63)
            .having((v) => v.vote, 'vote', SeatVote.pour),
      );
    });

    test('non-votants', () {
      final votants = [for (final g in fixture(8706).groupVotes) ...g.votants];
      expect(votants.where((v) => v.vote == SeatVote.nonVotant), hasLength(1));
    });
  });

  group('sièges du scrutin', () {
    test('8706 : 503 pour, 0 contre, 67 abstentions', () {
      final seats = hemicycleSeats(fixture(8706), groups);
      expect(seats, hasLength(574));
      expect(countOf(seats, SeatVote.pour), 503);
      expect(countOf(seats, SeatVote.contre), 0);
      expect(countOf(seats, SeatVote.abstention), 67);
      expect(countOf(seats, SeatVote.nonVotant), 1);
      expect(countOf(seats, SeatVote.absent), 3);
      expect(
        seats.map((s) => s.place),
        orderedEquals([...seats.map((s) => s.place)]..sort()),
      );
    });

    test('8610 : 151 pour, 187 contre', () {
      final seats = hemicycleSeats(fixture(8610), groups);
      expect(seats, hasLength(574));
      expect(countOf(seats, SeatVote.pour), 151);
      expect(countOf(seats, SeatVote.contre), 187);
      expect(countOf(seats, SeatVote.abstention), 0);
      expect(countOf(seats, SeatVote.absent), 235);
    });

    test('identiques aux sièges des maquettes (design/maquettes)', () {
      final reference =
          jsonDecode(
                File('../design/maquettes/data/seats.json').readAsStringSync(),
              )
              as Map<String, Object?>;
      const votes = {
        'pour': 'p',
        'contre': 'c',
        'abst': 'a',
        'nv': 'n',
        'absent': 'x',
      };
      for (final numero in [8706, 8610]) {
        final expected = [
          for (final s
              in (reference['$numero'] as Map<String, Object?>)['seats']
                  as List)
            '${(s as Map)['place']} ${s['g']} ${votes[s['v']]}',
        ];
        expect(
          [
            for (final s in hemicycleSeats(fixture(numero), groups))
              '${s.place} ${groups[s.group]!.abbreviation} ${s.vote.json}',
          ],
          expected,
          reason: '$numero',
        );
      }
    });
  });

  group('assertions : le job refuse des sièges incohérents', () {
    test('effectif d\'un groupe différent de son nombre de sièges', () {
      // Un député par groupe seulement : les absents manquent.
      final partial = GroupDirectory.fromArchive(organesArchive());
      expect(
        () => hemicycleSeats(fixture(8706), partial),
        throwsA(
          isA<SeatsMismatch>().having(
            (e) => e.message,
            'message',
            contains('effectif'),
          ),
        ),
      );
    });

    test('pour, contre ou abstentions différents du décompte publié', () {
      final json = fixtureFile(8706).readAsStringSync().replaceFirst(
        '"decompte": {"nonVotants": "1", "pour": "503"',
        '"decompte": {"nonVotants": "1", "pour": "504"',
      );
      expect(json, contains('"pour": "504"'));
      expect(
        () => hemicycleSeats(parseScrutinJson(json), groups),
        throwsA(
          isA<SeatsMismatch>().having(
            (e) => e.message,
            'message',
            contains('décompte'),
          ),
        ),
      );
    });

    test('LFI-NFP pas le plus à gauche ou RN pas le plus à droite', () {
      // Sigles inversés : les sièges des « LFI-NFP » sont à droite.
      final swapped = GroupDirectory.fromArchive(
        hemicycleArchive(
          abbreviations: {'PO845401': 'LFI-NFP', 'PO845413': 'RN'},
        ),
      );
      expect(
        () => hemicycleSeats(fixture(8706), swapped),
        throwsA(
          isA<SeatsMismatch>().having(
            (e) => e.message,
            'message',
            contains('gauche'),
          ),
        ),
      );
    });

    test('un votant sans place connue', () {
      final json = fixtureFile(8706).readAsStringSync().replaceFirst(
        '"numPlace": "063"',
        '"numPlace": null',
      );
      final empty = GroupDirectory.fromJson({
        ...groups.toJson(),
        'seats': <String, Object?>{},
      });
      expect(
        () => hemicycleSeats(parseScrutinJson(json), empty),
        throwsA(isA<SeatsMismatch>()),
      );
    });
  });

  group('fichier de détail', () {
    DecisionDetail detailOf(
      int numero,
      GroupDirectory directory, {
      List<String>? warnings,
    }) {
      final scrutin = fixture(numero);
      final index = buildDecisionIndex([scrutin], generatedAt: clock);
      return buildDecisionDetails(
        [scrutin],
        index,
        groups: directory,
        warnings: warnings,
      ).single;
    }

    test('sièges et couleurs des groupes', () {
      final detail = detailOf(8706, groups);
      expect(detail.seats, hemicycleSeats(fixture(8706), groups));
      final rn = detail.groups.firstWhere((g) => g.organeRef == 'PO845401');
      expect(rn.color, '#313567');
      final json = jsonDecode(encodeDecisionDetail(detail)) as Map;
      expect((json['seats'] as List).first, [1, 'PO845401', 'p']);
    });

    test('sièges incohérents : détail publié sans sièges, avertissement', () {
      final warnings = <String>[];
      final detail = detailOf(
        8706,
        GroupDirectory.fromArchive(organesArchive()),
        warnings: warnings,
      );
      expect(detail.seats, isNull);
      expect(detail.groups, hasLength(12));
      expect(detail.toJson().containsKey('seats'), isFalse);
      expect(warnings.single, allOf(contains('8706'), contains('effectif')));
    });

    test('sans annuaire : pas de sièges', () {
      final scrutin = fixture(8706);
      final index = buildDecisionIndex([scrutin], generatedAt: clock);
      expect(buildDecisionDetails([scrutin], index).single.seats, isNull);
    });

    test('décision provisoire (en direct) : pas de sièges', () {
      final scrutin = fixture(8706);
      final summary = buildDecisionIndex([
        scrutin,
      ], generatedAt: clock).decisions.single;
      final provisional = DecisionSummary.tryFromJson({
        ...summary.toJson(),
        'status': DecisionStatus.provisoire.json,
      })!;
      final detail = buildDecisionDetail(
        provisional,
        scrutin: scrutin,
        groups: groups,
      );
      expect(detail.seats, isNull);
    });

    test('à main levée : pas de sièges', () {
      final summary = DecisionSummary(
        id: 'L17-VD234087DEC',
        voteMode: VoteMode.mainLevee,
        type: DecisionType.ensembleTexte,
        status: DecisionStatus.confirmee,
        result: VoteResult.adopte,
        date: DateTime.utc(2026, 10, 7),
        officialTitle: 'projet de loi exemple',
        sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/dossiers/X',
      );
      expect(buildDecisionDetail(summary, groups: groups).seats, isNull);
    });
  });

  test('le job publie les sièges dans le fichier de détail', () async {
    final dir = Directory.systemTemp.createTempSync('vote_job_seats');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = LocalDirectoryStore(dir.path);
    final outcome = await runJob(
      source: FakeDumpSource(
        'Sun, 25 Oct 2026 10:30:00 GMT',
        archive: () => fixtureArchive(numeros: [8706, 8610]),
      ),
      organes: FakeDumpSource(
        'Sun, 25 Oct 2026 00:00:34 GMT',
        archive: hemicycleArchive,
      ),
      store: store,
      clock: () => clock,
    );
    expect(outcome, isA<JobPublished>());
    for (final (numero, pour, contre) in [(8706, 503, 0), (8610, 151, 187)]) {
      final detail = DecisionDetail.fromJson(
        jsonDecode(
          (await store.read(decisionDetailPath('VTANR5L17V$numero')))!,
        ),
      );
      expect(countOf(detail.seats!, SeatVote.pour), pour, reason: '$numero');
      expect(countOf(detail.seats!, SeatVote.contre), contre);
    }
  });
}
