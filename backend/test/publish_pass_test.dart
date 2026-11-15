import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

const _base = 'https://pub.test';
const _bsky = 'https://bsky.test';
final _day = DateTime.utc(2026, 10, 9);

final _detail = DecisionDetail.fromJson(
  jsonDecode(File('test/fixtures/content/detail_8610.json').readAsStringSync()),
);
final _id = _detail.decision.id;
const _title = 'Donner aux acheteurs publics un critère de priorité nationale';

/// En-tête PNG d'une image 1080 × 1350 (signature et IHDR).
final _png = [
  ...[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
  ...[0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52],
  ...[0, 0, 0x04, 0x38, 0, 0, 0x05, 0x46],
];

/// Bucket public de test : le détail de 8610 et sa carte.
MockClient _bucket() => MockClient((request) async {
  final path = request.url.path;
  if (path == '/${decisionDetailPath(_id)}') {
    return http.Response.bytes(utf8.encode(jsonEncode(_detail.toJson())), 200);
  }
  if (path == '/${draftImageKey(_day, _id)}') {
    return http.Response.bytes(_png, 200);
  }
  return http.Response('', 404);
});

/// Faux serveur Bluesky : garde les posts créés.
class _FakeBluesky {
  final records = <Map<String, Object?>>[];
  var uploads = 0;
  var failPosts = false;

  late final client = MockClient((request) async {
    switch (request.url.path) {
      case '/xrpc/com.atproto.server.createSession':
        expect(jsonDecode(request.body), {
          'identifier': 'leperchoir.app',
          'password': 'mdp-app',
        });
        return _json({'accessJwt': 'jwt', 'did': 'did:plc:test'});
      case '/xrpc/com.atproto.repo.listRecords':
        expect(request.url.queryParameters['repo'], 'did:plc:test');
        return _json({
          'records': [
            for (final (i, r) in records.indexed)
              {'uri': 'at://did:plc:test/app.bsky.feed.post/r$i', 'value': r},
          ],
        });
      case '/xrpc/com.atproto.repo.uploadBlob':
        expect(request.headers['Authorization'], 'Bearer jwt');
        expect(request.headers['Content-Type'], 'image/png');
        uploads++;
        return _json({
          'blob': {r'$type': 'blob', 'size': request.bodyBytes.length},
        });
      case '/xrpc/com.atproto.repo.createRecord':
        if (failPosts) return http.Response('{"error":"Down"}', 502);
        final json = jsonDecode(request.body) as Map;
        expect(json['collection'], 'app.bsky.feed.post');
        records.add((json['record'] as Map).cast());
        return _json({
          'uri': 'at://did:plc:test/app.bsky.feed.post/r${records.length - 1}',
          'cid': 'c',
        });
    }
    return http.Response('', 404);
  });

  BlueskyClient get bluesky => BlueskyClient(
    client: client,
    handle: 'leperchoir.app',
    appPassword: 'mdp-app',
    service: _bsky,
  );
}

http.Response _json(Object json) => http.Response(
  jsonEncode(json),
  200,
  headers: {'content-type': 'application/json'},
);

/// Issue du jour en mémoire ; [failWrites] simule une panne de GitHub.
class _FakeIssue implements IssueBody {
  _FakeIssue(this.body);
  String body;
  var failWrites = false;

  @override
  Future<String> read() async => body;

  @override
  Future<void> write(String body) async {
    if (failWrites) throw const HttpException('GitHub en panne');
    this.body = body;
  }
}

String _issue({required bool needsTitle}) => renderDailyIssue(_day, [
  needsTitle
      ? Draft(
          decisionId: _id,
          sourceUrl: _detail.decision.sourceUrl,
          title: null,
        )
      : Draft(
          decisionId: _id,
          sourceUrl: _detail.decision.sourceUrl,
          title: _title,
          text: postText(_detail, title: _title),
          alt: altText(_detail, title: _title),
          imageUrl: '$_base/${draftImageKey(_day, _id)}',
        ),
]);

String _checked(String body) =>
    body.replaceFirst('- [ ] Publier ce post', '- [x] Publier ce post');

void main() {
  late Directory dir;
  late _FakeBluesky server;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('publish');
    server = _FakeBluesky();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<PublishReport> publish(_FakeIssue issue) async {
    await planReview(
      client: _bucket(),
      baseUrl: _base,
      body: issue.body,
      dir: dir,
      checkedOnly: true,
    );
    return publishDrafts(
      bluesky: server.bluesky,
      issue: issue,
      dir: dir,
      now: DateTime.utc(2026, 10, 9, 14),
    );
  }

  test(
    'brouillon coché : publié avec image, texte alternatif et lien',
    () async {
      final issue = _FakeIssue(_checked(_issue(needsTitle: false)));
      final report = await publish(issue);

      expect(report.done, isTrue);
      expect(report.blocked, isEmpty);
      const url = 'https://bsky.app/profile/leperchoir.app/post/r0';
      expect(report.published.single.url, url);
      final record = server.records.single;
      final text = postText(_detail, title: _title);
      expect(record['text'], text);
      expect(record['langs'], ['fr']);
      expect(record['createdAt'], '2026-10-09T14:00:00.000Z');
      final image = ((record['embed']! as Map)['images'] as List).single as Map;
      expect(image['alt'], altText(_detail, title: _title));
      expect(image['aspectRatio'], {'width': 1080, 'height': 1350});
      final facet = (record['facets']! as List).single as Map;
      final index = facet['index'] as Map;
      expect(
        utf8.decode(
          utf8
              .encode(text)
              .sublist(index['byteStart'] as int, index['byteEnd'] as int),
        ),
        'leperchoir.app',
      );
      expect(parseDailyIssue(issue.body).single.postUrl, url);
      expect(publishComment(report), contains('- [$_title]($url)'));
    },
  );

  test('relancer après publication ne publie rien deux fois', () async {
    final issue = _FakeIssue(_checked(_issue(needsTitle: false)));
    await publish(issue);
    final again = await publish(issue);
    expect(server.records, hasLength(1));
    expect(again.done, isTrue);
    expect(again.published.single.url, endsWith('/r0'));
  });

  test('panne après le post : relancer retrouve le post en ligne', () async {
    final issue = _FakeIssue(_checked(_issue(needsTitle: false)))
      ..failWrites = true;
    await expectLater(publish(issue), throwsA(isA<HttpException>()));
    expect(server.records, hasLength(1));

    issue.failWrites = false;
    final report = await publish(issue);
    expect(server.records, hasLength(1));
    expect(report.done, isTrue);
    expect(parseDailyIssue(issue.body).single.postUrl, endsWith('/r0'));
  });

  test('panne de Bluesky : rien d\'écrit, relancer publie', () async {
    final issue = _FakeIssue(_checked(_issue(needsTitle: false)));
    server.failPosts = true;
    await expectLater(publish(issue), throwsA(isA<HttpException>()));
    expect(parseDailyIssue(issue.body).single.postUrl, isNull);
    server.failPosts = false;
    expect((await publish(issue)).done, isTrue);
    expect(server.records, hasLength(1));
  });

  test('brouillon non coché : jamais publié', () async {
    final issue = _FakeIssue(_issue(needsTitle: false));
    final report = await publish(issue);
    expect(server.records, isEmpty);
    expect(report.done, isFalse);
    expect(publishComment(report), startsWith('Aucun post coché'));
  });

  test('« titre à écrire » vide : jamais publié', () async {
    final issue = _FakeIssue(_checked(_issue(needsTitle: true)));
    final report = await publish(issue);
    expect(server.records, isEmpty);
    expect(report.done, isFalse);
    expect(report.blocked.single.problems.single, contains('titre à écrire'));
  });

  test('texte édité en échec de relecture : bloqué, pas publié', () async {
    final issue = _FakeIssue(
      _checked(_issue(needsTitle: false)).replaceFirst('151 pour', '152 pour'),
    );
    final report = await publish(issue);
    expect(server.records, isEmpty);
    expect(server.uploads, 0);
    expect(report.done, isFalse);
    expect(
      report.blocked.single.problems,
      contains(contains('152 pour au lieu de 151')),
    );
    expect(publishComment(report), contains('Publication incomplète'));
  });

  test('titre écrit à la main : carte rendue et textes produits', () async {
    const written = 'Priorité nationale : achats publics';
    final issue = _FakeIssue(
      _checked(_issue(needsTitle: true)).replaceFirst(
        '**Titre**\n\n```text\n\n```',
        '**Titre**\n\n```text\n$written\n```',
      ),
    );
    await planReview(
      client: _bucket(),
      baseUrl: _base,
      body: issue.body,
      dir: dir,
      checkedOnly: true,
    );
    // Rendu de la carte (outil Flutter) simulé.
    File('${dir.path}/$_id.png').writeAsBytesSync(_png);
    File('${dir.path}/$_id.png.json').writeAsStringSync(
      jsonEncode({'status': 'ok', 'title': written, 'titleSize': 84}),
    );
    final report = await publishDrafts(
      bluesky: server.bluesky,
      issue: issue,
      dir: dir,
    );
    expect(report.done, isTrue);
    final record = server.records.single;
    expect(record['text'], startsWith('Rejeté — Priorité nationale'));
    final image = ((record['embed']! as Map)['images'] as List).single as Map;
    expect(image['alt'], altText(_detail, title: frenchTypography(written)));
  });

  test('titre écrit trop long pour la carte : bloqué', () async {
    final issue = _FakeIssue(
      _checked(_issue(needsTitle: true)).replaceFirst(
        '**Titre**\n\n```text\n\n```',
        '**Titre**\n\n```text\n${'Interdire ' * 40}\n```',
      ),
    );
    await planReview(
      client: _bucket(),
      baseUrl: _base,
      body: issue.body,
      dir: dir,
      checkedOnly: true,
    );
    File(
      '${dir.path}/$_id.png.json',
    ).writeAsStringSync(jsonEncode({'status': 'titre_a_ecrire'}));
    final report = await publishDrafts(
      bluesky: server.bluesky,
      issue: issue,
      dir: dir,
    );
    expect(server.records, isEmpty);
    expect(report.blocked.single.problems.single, contains('raccourcis-le'));
  });

  test('lien cliquable : positions en octets malgré les accents', () {
    const text = 'Adopté — Été.\nleperchoir.app';
    final index = (linkFacets(text).single['index']! as Map);
    expect(index['byteStart'], utf8.encode('Adopté — Été.\n').length);
    expect(index['byteEnd'], utf8.encode(text).length);
    expect(linkFacets('sans lien'), isEmpty);
  });

  test('taille d\'une image PNG', () {
    expect(pngSize(_png), (1080, 1350));
  });
}
