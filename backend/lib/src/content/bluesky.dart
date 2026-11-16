import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'post_text.dart';

/// Taille maximale d'une image sur Bluesky (`app.bsky.embed.images`).
const blueskyImageMaxBytes = 1000000;

/// Client Bluesky minimal (#112) : session par mot de passe d'application,
/// envoi d'une image, post avec image, texte alternatif et lien cliquable.
class BlueskyClient {
  BlueskyClient({
    required http.Client client,
    required String handle,
    required String appPassword,
    this.service = 'https://bsky.social',
  }) : _client = client,
       _handle = handle,
       _password = appPassword;

  final http.Client _client;
  final String _handle;
  final String _password;
  final String service;

  String? _jwt;
  String? _did;

  Future<void> _login() async {
    if (_jwt != null) return;
    final session = await _post(
      'com.atproto.server.createSession',
      jsonEncode({'identifier': _handle, 'password': _password}),
      auth: false,
    );
    _jwt = session['accessJwt']! as String;
    _did = session['did']! as String;
  }

  /// Le post du compte dont le texte est [text] parmi les 50 derniers, ou
  /// `null` : un post publié dont le lien n'a pas pu être écrit dans l'issue
  /// n'est pas republié quand on relance.
  Future<PostRef?> findPost(String text) async {
    await _login();
    final uri = Uri.parse('$service/xrpc/com.atproto.repo.listRecords').replace(
      queryParameters: {
        'repo': _did!,
        'collection': 'app.bsky.feed.post',
        'limit': '50',
      },
    );
    final response = await _client.get(uri, headers: _headers());
    final json = _decode(response, 'listRecords');
    for (final r in (json['records'] as List? ?? const [])) {
      if (r is! Map) continue;
      final value = r['value'];
      if (value is Map && value['text'] == text) return _ref(r);
    }
    return null;
  }

  /// Publie [text] avec l'image PNG [image] ([width] × [height]) et son
  /// texte alternatif [alt].
  Future<PostRef> post({
    required String text,
    required List<int> image,
    required String alt,
    required int width,
    required int height,
    DateTime? now,
  }) async {
    await _login();
    final upload = await _client.post(
      Uri.parse('$service/xrpc/com.atproto.repo.uploadBlob'),
      headers: _headers(contentType: 'image/png'),
      body: image,
    );
    final blob = _decode(upload, 'uploadBlob')['blob'];
    return _create(
      postRecord(
        text: text,
        blob: blob,
        alt: alt,
        width: width,
        height: height,
        createdAt: now ?? DateTime.now().toUtc(),
      ),
    );
  }

  /// Publie [text] en réponse au post [parent], dans le fil ouvert par
  /// [root].
  Future<PostRef> reply({
    required String text,
    required PostRef root,
    required PostRef parent,
    DateTime? now,
  }) async {
    await _login();
    return _create(
      replyRecord(
        text: text,
        root: root,
        parent: parent,
        createdAt: now ?? DateTime.now().toUtc(),
      ),
    );
  }

  Future<PostRef> _create(Map<String, Object?> record) async => _ref(
    await _post(
      'com.atproto.repo.createRecord',
      jsonEncode({
        'repo': _did,
        'collection': 'app.bsky.feed.post',
        'record': record,
      }),
    ),
  );

  PostRef _ref(Map<Object?, Object?> record) {
    final uri = record['uri']! as String;
    return (uri: uri, cid: record['cid']! as String, url: _webUrl(uri));
  }

  String _webUrl(String atUri) =>
      'https://bsky.app/profile/$_handle/post/${atUri.split('/').last}';

  Map<String, String> _headers({String? contentType}) => {
    'Authorization': 'Bearer $_jwt',
    'Content-Type': ?contentType,
  };

  Future<Map<String, Object?>> _post(
    String method,
    String body, {
    bool auth = true,
  }) async {
    final response = await _client.post(
      Uri.parse('$service/xrpc/$method'),
      headers: auth
          ? _headers(contentType: 'application/json')
          : {'Content-Type': 'application/json'},
      body: body,
    );
    return _decode(response, method);
  }

  Map<String, Object?> _decode(http.Response response, String method) {
    if (response.statusCode != 200) {
      // Le corps d'erreur de l'API ne contient ni jeton ni mot de passe.
      throw HttpException(
        'Bluesky $method : HTTP ${response.statusCode} ${response.body}',
      );
    }
    return (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
        .cast<String, Object?>();
  }
}

/// Un post publié : son adresse AT ([uri]) et son empreinte ([cid]), qu'une
/// réponse cite pour s'y rattacher, et son lien bsky.app ([url]).
typedef PostRef = ({String uri, String cid, String url});

/// Enregistrement `app.bsky.feed.post` : texte en français, liens et
/// mots-dièse cliquables ([richTextFacets]), image avec son texte alternatif
/// et ses proportions.
Map<String, Object?> postRecord({
  required String text,
  required Object? blob,
  required String alt,
  required int width,
  required int height,
  required DateTime createdAt,
}) => {
  r'$type': 'app.bsky.feed.post',
  'text': text,
  'createdAt': createdAt.toUtc().toIso8601String(),
  'langs': ['fr'],
  'facets': richTextFacets(text),
  'embed': {
    r'$type': 'app.bsky.embed.images',
    'images': [
      {
        'image': blob,
        'alt': alt,
        'aspectRatio': {'width': width, 'height': height},
      },
    ],
  },
};

/// Enregistrement d'une réponse à [parent], sans image, dans le fil ouvert
/// par [root].
Map<String, Object?> replyRecord({
  required String text,
  required PostRef root,
  required PostRef parent,
  required DateTime createdAt,
}) => {
  r'$type': 'app.bsky.feed.post',
  'text': text,
  'createdAt': createdAt.toUtc().toIso8601String(),
  'langs': ['fr'],
  'facets': richTextFacets(text),
  'reply': {
    'root': {'uri': root.uri, 'cid': root.cid},
    'parent': {'uri': parent.uri, 'cid': parent.cid},
  },
};

// Ce que Bluesky rend cliquable : une adresse complète, le domaine de
// l'Assemblée ou [postLink] écrits sans `https://`, un mot-dièse.
final _rich = RegExp(
  r'(https?://[^\s]+)'
  r'|((?<![\p{L}\p{N}./-])(?:assemblee-nationale\.fr/[^\s]+|leperchoir\.app)(?![\p{L}\p{N}-]))'
  r'|((?<![\p{L}\p{N}])#[\p{L}][\p{L}\p{N}_]*)',
  unicode: true,
);
final _trailingPunctuation = RegExp(r'[.,;:!?)»]+$');

/// Facettes de [text] : liens (`https://…`, `assemblee-nationale.fr/…` et
/// [postLink], complétés en adresse) et mots-dièse, positions en octets
/// UTF-8 comme le veut le protocole.
List<Map<String, Object?>> richTextFacets(String text) {
  final facets = <Map<String, Object?>>[];
  for (final m in _rich.allMatches(text)) {
    final raw = m[0]!;
    final tag = m[3] != null;
    final shown = tag ? raw : raw.replaceFirst(_trailingPunctuation, '');
    final start = utf8.encode(text.substring(0, m.start)).length;
    facets.add({
      'index': {
        'byteStart': start,
        'byteEnd': start + utf8.encode(shown).length,
      },
      'features': [
        if (tag)
          {r'$type': 'app.bsky.richtext.facet#tag', 'tag': shown.substring(1)}
        else
          {
            r'$type': 'app.bsky.richtext.facet#link',
            'uri': switch (shown) {
              _ when m[1] != null => shown,
              postLink => 'https://$postLink',
              _ => 'https://www.$shown',
            },
          },
      ],
    });
  }
  return facets;
}
