import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

const _base = 'https://pub.test';
final _day = DateTime.utc(2026, 10, 9);

final _detail = DecisionDetail.fromJson(
  jsonDecode(File('test/fixtures/content/detail_8610.json').readAsStringSync()),
);
final _id = _detail.decision.id;
const _title = 'Donner aux acheteurs publics un critère de priorité nationale';

/// Bucket public de test : le détail de 8610 et sa carte.
MockClient _server() => MockClient((request) async {
  final path = request.url.path;
  if (path == '/${decisionDetailPath(_id)}') {
    return http.Response.bytes(utf8.encode(jsonEncode(_detail.toJson())), 200);
  }
  if (path == '/${draftImageKey(_day, _id)}') {
    return http.Response.bytes([1, 2, 3], 200);
  }
  return http.Response('', 404);
});

String _issue({required bool needsTitle}) {
  final text = postText(_detail, title: _title);
  return renderDailyIssue(_day, [
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
            text: text,
            alt: altText(_detail, title: _title),
            imageUrl: '$_base/${draftImageKey(_day, _id)}',
          ),
  ]);
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('review'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<String> review(String body) async {
    await planReview(client: _server(), baseUrl: _base, body: body, dir: dir);
    return buildReviewComment(
      store: LocalDirectoryStore('${dir.path}/store'),
      publicBaseUrl: _base,
      body: body,
      dir: dir,
      version: '7',
    );
  }

  test('texte édité : relu tel qu\'édité, carte téléchargée', () async {
    final body = _issue(needsTitle: false).replaceFirst('151 pour', '152 pour');
    await planReview(client: _server(), baseUrl: _base, body: body, dir: dir);
    expect(jsonDecode(File('${dir.path}/review.json').readAsStringSync()), [
      {'id': _id, 'render': false},
    ]);
    expect(File('${dir.path}/$_id.png').readAsBytesSync(), [1, 2, 3]);
    expect(
      File('${dir.path}/$_id.post.txt').readAsStringSync(),
      contains('152 pour'),
    );
    final comment = await buildReviewComment(
      store: LocalDirectoryStore('${dir.path}/store'),
      publicBaseUrl: _base,
      body: body,
      dir: dir,
      version: '7',
    );
    expect(comment, startsWith(reviewCommentMarker));
    expect(comment, contains('post : 152 pour au lieu de 151'));
  });

  test('texte intact : relecture OK, aperçu envoyé et versionné', () async {
    final body = _issue(needsTitle: false);
    await planReview(client: _server(), baseUrl: _base, body: body, dir: dir);
    File('${dir.path}/$_id-apercu.png').writeAsBytesSync([9]);
    final comment = await buildReviewComment(
      store: LocalDirectoryStore('${dir.path}/store'),
      publicBaseUrl: _base,
      body: body,
      dir: dir,
      version: '7',
    );
    expect(comment, contains('✅ Relecture OK'));
    final key = draftPreviewKey(_day, _id, version: '7');
    expect(key, 'content/2026-10-09/$_id-apercu-7.png');
    expect(comment, contains('<img src="$_base/$key"'));
    expect(File('${dir.path}/store/$key').readAsBytesSync(), [9]);
  });

  test('titre écrit à la main : carte à rendre, textes produits', () async {
    final body = _issue(needsTitle: true).replaceFirst(
      '**Titre**\n\n```text\n\n```',
      '**Titre**\n\n```text\nPriorité nationale : achats publics\n```',
    );
    await planReview(client: _server(), baseUrl: _base, body: body, dir: dir);
    expect(jsonDecode(File('${dir.path}/review.json').readAsStringSync()), [
      {'id': _id, 'render': true},
    ]);
    expect(
      File('${dir.path}/$_id.title.txt').readAsStringSync(),
      'Priorité nationale : achats publics',
    );
    // Rendu de la carte (outil Flutter) simulé.
    File('${dir.path}/$_id.png.json').writeAsStringSync(
      jsonEncode({'status': 'ok', 'title': 'x', 'titleSize': 84}),
    );
    final comment = await buildReviewComment(
      store: LocalDirectoryStore('${dir.path}/store'),
      publicBaseUrl: _base,
      body: body,
      dir: dir,
      version: '7',
    );
    expect(comment, contains('Texte produit avec ton titre'));
    expect(comment, contains('Rejeté — Priorité nationale : achats publics.'));
    expect(comment, contains('✅ Relecture OK'));
  });

  test('titre écrit trop long : à raccourcir', () async {
    final body = _issue(needsTitle: true).replaceFirst(
      '**Titre**\n\n```text\n\n```',
      '**Titre**\n\n```text\n${'Interdire ' * 40}\n```',
    );
    await planReview(client: _server(), baseUrl: _base, body: body, dir: dir);
    File(
      '${dir.path}/$_id.png.json',
    ).writeAsStringSync(jsonEncode({'status': 'titre_a_ecrire'}));
    expect(
      await buildReviewComment(
        store: LocalDirectoryStore('${dir.path}/store'),
        publicBaseUrl: _base,
        body: body,
        dir: dir,
        version: '7',
      ),
      contains('raccourcis-le'),
    );
  });

  test('titre pas encore écrit ou post déjà publié : rien à relire', () async {
    expect(await review(_issue(needsTitle: true)), isNot(contains('####')));
    final posted = _issue(needsTitle: false).replaceFirst(
      '<!-- original:',
      'Publié : https://bsky.app/post/1\n\n<!-- original:',
    );
    expect(await review(posted), isNot(contains('####')));
  });

  test('jour de l\'issue lu dans son en-tête', () {
    expect(dailyIssueDay(_issue(needsTitle: false)), _day);
    expect(dailyIssueDay('autre chose'), isNull);
  });
}
