import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

const _base = 'https://pub.test';

/// Détail réel de la résolution 8610 (8 octobre 2026), avec groupes et
/// sièges.
final _detail = DecisionDetail.fromJson(
  jsonDecode(File('test/fixtures/content/detail_8610.json').readAsStringSync()),
);

/// Le lendemain du vote, à [hour] h UTC.
DateTime _dayAfter(int hour) => DateTime.utc(2026, 10, 9, hour);

MockClient _server({bool withDetail = true}) => MockClient((request) async {
  final path = request.url.path;
  if (path == '/$indexPath') {
    return http.Response.bytes(
      utf8.encode(
        jsonEncode(
          DecisionIndex(
            generatedAt: _dayAfter(11),
            decisions: [_detail.decision],
          ).toJson(),
        ),
      ),
      200,
    );
  }
  if (withDetail && path == '/${decisionDetailPath(_detail.decision.id)}') {
    return http.Response.bytes(utf8.encode(jsonEncode(_detail.toJson())), 200);
  }
  return http.Response('', 404);
});

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('content'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<List<SelectedDecision>> select({
    required DateTime now,
    Set<String> handled = const {},
    bool withDetail = true,
  }) => selectDailyDrafts(
    client: _server(withDetail: withDetail),
    baseUrl: _base,
    handled: handled,
    now: now,
    dir: dir,
  );

  test('après 13 h (Paris) : décision retenue, détail écrit', () async {
    // 12 h UTC = 14 h à Paris en octobre (heure d'été).
    final selected = await select(now: _dayAfter(12));
    expect(selected.map((s) => s.id), [_detail.decision.id]);
    expect(
      selected.single.title,
      'Donner aux acheteurs publics un critère de priorité nationale',
    );
    expect(jsonDecode(File('${dir.path}/selection.json').readAsStringSync()), [
      _detail.decision.id,
    ]);
    final written = DecisionDetail.fromJson(
      jsonDecode(
        File('${dir.path}/${_detail.decision.id}.json').readAsStringSync(),
      ),
    );
    expect(written.seats, hasLength(_detail.seats!.length));
  });

  test(
    'avant 13 h (Paris) : rien, le jeu de données n\'est pas arrivé',
    () async {
      // 10 h UTC = 12 h à Paris.
      expect(await select(now: _dayAfter(10)), isEmpty);
    },
  );

  test('déjà traitée ou sans détail publié : rien', () async {
    expect(
      await select(now: _dayAfter(12), handled: {_detail.decision.id}),
      isEmpty,
    );
    expect(await select(now: _dayAfter(12), withDetail: false), isEmpty);
  });

  test('corps de l\'issue : carte envoyée, textes, titre à écrire', () async {
    await select(now: _dayAfter(12));
    final id = _detail.decision.id;
    File('${dir.path}/$id.png').writeAsBytesSync([1, 2, 3]);
    final store = LocalDirectoryStore('${dir.path}/store');
    final day = DateTime.utc(2026, 10, 9);

    File('${dir.path}/$id.png.json').writeAsStringSync(
      jsonEncode({
        'status': 'ok',
        'title': 'Priorité nationale',
        'titleSize': 84,
      }),
    );
    final body = await buildDailyIssue(
      store: store,
      publicBaseUrl: _base,
      parisDay: day,
      dir: dir,
    );
    expect(
      File('${dir.path}/store/content/2026-10-09/$id.png').readAsBytesSync(),
      [1, 2, 3],
    );
    final draft = parseDailyIssue(body).single;
    expect(draft.imageUrl, '$_base/content/2026-10-09/$id.png');
    expect(draft.text, startsWith('Rejeté — Priorité nationale.\n'));
    expect(draft.alt, startsWith('Carte Le Perchoir.'));

    File(
      '${dir.path}/$id.png.json',
    ).writeAsStringSync(jsonEncode({'status': 'titre_a_ecrire'}));
    final toTitle = parseDailyIssue(
      await buildDailyIssue(
        store: store,
        publicBaseUrl: _base,
        parisDay: day,
        dir: dir,
      ),
    ).single;
    expect(toTitle.needsTitle, isTrue);
    expect(toTitle.imageUrl, isNull);
  });

  test('aucun brouillon : corps vide, pas d\'issue', () async {
    File('${dir.path}/selection.json').writeAsStringSync('[]');
    expect(
      await buildDailyIssue(
        store: LocalDirectoryStore('${dir.path}/store'),
        publicBaseUrl: _base,
        parisDay: DateTime.utc(2026, 10, 9),
        dir: dir,
      ),
      isEmpty,
    );
  });
}
