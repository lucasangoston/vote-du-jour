import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:vote_job/vote_job.dart';

Draft _draft(String id) => Draft(
  decisionId: id,
  sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/1',
  title: 'Titre $id',
  text: 'Adopté — Titre $id.\nleperchoir.app',
  alt: 'Carte Le Perchoir.',
  imageUrl: 'https://pub.r2.dev/$id.png',
);

/// Issue du [day] dont chaque brouillon de [ids] est publié (post `<id>`).
String _published(DateTime day, List<String> ids) {
  var body = renderDailyIssue(day, [for (final id in ids) _draft(id)]);
  for (final id in ids) {
    body = markPublished(
      body,
      id,
      'https://bsky.app/profile/leperchoir.app/post/$id',
    );
  }
  return body;
}

void main() {
  test('audience des posts publiés, du plus récent au plus ancien', () async {
    final asked = <Uri>[];
    final client = MockClient((request) async {
      asked.add(request.url);
      switch (request.url.path) {
        case '/xrpc/com.atproto.identity.resolveHandle':
          return http.Response(jsonEncode({'did': 'did:plc:test'}), 200);
        case '/xrpc/app.bsky.feed.getPosts':
          return http.Response(
            jsonEncode({
              'posts': [
                // « B » supprimé : absent de la réponse.
                for (final id in request.url.queryParametersAll['uris']!)
                  if (!id.endsWith('/B'))
                    {
                      'uri': id,
                      'likeCount': id.endsWith('/C') ? 7 : 1,
                      'repostCount': 2,
                      'replyCount': 0,
                      'quoteCount': 4,
                    },
              ],
            }),
            200,
          );
      }
      return http.Response('', 404);
    });
    final stats = await fetchPostStats(
      client: client,
      service: 'https://bsky.test',
      bodies: [
        _published(DateTime.utc(2026, 11, 13), ['A', 'B']),
        _published(DateTime.utc(2026, 11, 14), ['C']),
        renderDailyIssue(DateTime.utc(2026, 11, 15), [_draft('D')]),
      ],
    );
    expect([for (final s in stats) s.title], ['Titre C', 'Titre A']);
    expect(stats.first, (
      title: 'Titre C',
      url: 'https://bsky.app/profile/leperchoir.app/post/C',
      likes: 7,
      reposts: 2,
      replies: 0,
      quotes: 4,
    ));
    // Le compte n'est résolu qu'une fois.
    expect(asked.where((u) => u.path.endsWith('resolveHandle')), hasLength(1));
    expect(asked.last.queryParametersAll['uris'], [
      'at://did:plc:test/app.bsky.feed.post/C',
      'at://did:plc:test/app.bsky.feed.post/A',
      'at://did:plc:test/app.bsky.feed.post/B',
    ]);
  });

  test('aucun post publié : aucun appel', () async {
    final client = MockClient((_) async => fail('aucun appel attendu'));
    expect(
      await fetchPostStats(
        client: client,
        bodies: [
          renderDailyIssue(DateTime.utc(2026, 11, 15), [_draft('D')]),
        ],
      ),
      isEmpty,
    );
    expect(renderPostStats(const []), isEmpty);
  });
}
