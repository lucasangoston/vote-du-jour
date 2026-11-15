import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'daily_issue.dart';

/// Posts dont l'issue du jour rappelle l'audience.
const statsPostCount = 10;

/// L'audience d'un post publié, relevée sur Bluesky.
typedef PostStats = ({
  String title,
  String url,
  int likes,
  int reposts,
  int replies,
  int quotes,
});

final _postUrl = RegExp(r'^https://bsky\.app/profile/([^/]+)/post/([^/?#]+)');

/// Audience des [statsPostCount] derniers posts publiés depuis les issues du
/// jour [bodies] (ordre quelconque), du plus récent au plus ancien : ce qui
/// marche se lit dans l'issue du lendemain. Lecture de l'API publique de
/// Bluesky, sans compte. Un post supprimé est omis.
Future<List<PostStats>> fetchPostStats({
  required http.Client client,
  required Iterable<String> bodies,
  String service = 'https://public.api.bsky.app',
}) async {
  final posts =
      <({DateTime day, int order, String title, String url})>[
        for (final body in bodies)
          if (dailyIssueDay(body) case final day?)
            for (final (i, d) in parseDailyIssue(body).indexed)
              if (d.postUrl case final url? when _postUrl.hasMatch(url))
                (day: day, order: i, title: d.title ?? d.decisionId, url: url),
      ]..sort((a, b) {
        final byDay = b.day.compareTo(a.day);
        return byDay != 0 ? byDay : a.order.compareTo(b.order);
      });
  final recent = posts.take(statsPostCount).toList();
  if (recent.isEmpty) return const [];

  Future<Map<String, Object?>> get(
    String method,
    Map<String, Object> query,
  ) async {
    final response = await client.get(
      Uri.parse('$service/xrpc/$method').replace(queryParameters: query),
    );
    if (response.statusCode != 200) {
      throw HttpException('Bluesky $method : HTTP ${response.statusCode}');
    }
    return (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
        .cast<String, Object?>();
  }

  final dids = <String, String>{};
  final uris = <String, String>{};
  for (final p in recent) {
    final m = _postUrl.firstMatch(p.url)!;
    final handle = m[1]!;
    final did = handle.startsWith('did:')
        ? handle
        : dids[handle] ??=
              (await get('com.atproto.identity.resolveHandle', {
                    'handle': handle,
                  }))['did']!
                  as String;
    uris[p.url] = 'at://$did/app.bsky.feed.post/${m[2]}';
  }
  final found = <String, Map<Object?, Object?>>{
    for (final post
        in (await get('app.bsky.feed.getPosts', {
                  'uris': uris.values.toList(),
                }))['posts']
                as List? ??
            const [])
      if (post is Map && post['uri'] is String) post['uri']! as String: post,
  };
  int count(Map<Object?, Object?> post, String key) =>
      (post[key] as num?)?.toInt() ?? 0;
  return [
    for (final p in recent)
      if (found[uris[p.url]] case final post?)
        (
          title: p.title,
          url: p.url,
          likes: count(post, 'likeCount'),
          reposts: count(post, 'repostCount'),
          replies: count(post, 'replyCount'),
          quotes: count(post, 'quoteCount'),
        ),
  ];
}

/// Section de l'issue du jour : une ligne par post, du plus récent au plus
/// ancien. Vide sans post.
String renderPostStats(List<PostStats> stats) {
  if (stats.isEmpty) return '';
  final out = StringBuffer()
    ..writeln('<details><summary>Audience des derniers posts</summary>')
    ..writeln()
    ..writeln('| Post | J\'aime | Reposts | Citations | Réponses |')
    ..writeln('| --- | ---: | ---: | ---: | ---: |');
  for (final s in stats) {
    out.writeln(
      '| [${s.title.replaceAll('|', '/')}](${s.url}) | ${s.likes} | '
      '${s.reposts} | ${s.quotes} | ${s.replies} |',
    );
  }
  out
    ..writeln()
    ..write('</details>');
  return out.toString();
}
