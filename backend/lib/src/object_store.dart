import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Destination de publication : le bucket R2 en production, un dossier local
/// pour le développement et les tests.
abstract interface class ObjectStore {
  /// Contenu texte de [key], ou `null` s'il n'existe pas.
  Future<String?> read(String key);

  Future<void> write(
    String key,
    String body, {
    String contentType = 'application/json; charset=utf-8',
    String? cacheControl,
  });
}

/// Publie dans un dossier local (`<root>/<key>`).
class LocalDirectoryStore implements ObjectStore {
  LocalDirectoryStore(this.root);

  final String root;

  File _file(String key) => File(p.joinAll([root, ...key.split('/')]));

  @override
  Future<String?> read(String key) async {
    final file = _file(key);
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> write(
    String key,
    String body, {
    String contentType = 'application/json; charset=utf-8',
    String? cacheControl,
  }) async {
    final file = _file(key);
    await file.parent.create(recursive: true);
    await file.writeAsString(body);
  }
}

/// Publie dans un bucket Cloudflare R2 via son API compatible S3
/// (requêtes signées AWS Signature Version 4, région `auto`).
class R2Store implements ObjectStore {
  R2Store({
    required String accountId,
    required this.bucket,
    required this.accessKeyId,
    required this.secretAccessKey,
    http.Client? client,
    DateTime Function()? clock,
  }) : host = '$accountId.r2.cloudflarestorage.com',
       _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  final String host;
  final String bucket;
  final String accessKeyId;
  final String secretAccessKey;
  final http.Client _client;
  final DateTime Function() _clock;

  Uri _uri(String key) => Uri.https(host, '/$bucket/$key');

  @override
  Future<String?> read(String key) async {
    final uri = _uri(key);
    final response = await _client.get(
      uri,
      headers: _sign('GET', uri, const []),
    );
    if (response.statusCode == 404) return null;
    _check(response, 'GET $key');
    return utf8.decode(response.bodyBytes);
  }

  @override
  Future<void> write(
    String key,
    String body, {
    String contentType = 'application/json; charset=utf-8',
    String? cacheControl,
  }) async {
    final uri = _uri(key);
    final bytes = utf8.encode(body);
    final headers = _sign(
      'PUT',
      uri,
      bytes,
      extra: {'content-type': contentType, 'cache-control': ?cacheControl},
    );
    final response = await _client.put(uri, headers: headers, body: bytes);
    _check(response, 'PUT $key');
  }

  void _check(http.Response response, String what) {
    if (response.statusCode >= 300) {
      throw HttpException(
        'R2 $what : HTTP ${response.statusCode} ${response.body}',
      );
    }
  }

  Map<String, String> _sign(
    String method,
    Uri uri,
    List<int> payload, {
    Map<String, String> extra = const {},
  }) => signV4(
    method: method,
    uri: uri,
    headers: {'host': uri.host, ...extra},
    payload: payload,
    accessKeyId: accessKeyId,
    secretAccessKey: secretAccessKey,
    region: 'auto',
    service: 's3',
    now: _clock(),
  );
}

/// Signe une requête selon AWS Signature Version 4 et renvoie les en-têtes à
/// envoyer (ceux fournis, plus `x-amz-date`, `x-amz-content-sha256` et
/// `authorization`). [uri] ne doit pas contenir de paramètres de requête.
Map<String, String> signV4({
  required String method,
  required Uri uri,
  required Map<String, String> headers,
  required List<int> payload,
  required String accessKeyId,
  required String secretAccessKey,
  required String region,
  required String service,
  required DateTime now,
  bool signContentSha256 = true,
}) {
  final t = now.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final day = '${t.year}${two(t.month)}${two(t.day)}';
  final amzDate = '${day}T${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
  final payloadHash = sha256.convert(payload).toString();

  final all = <String, String>{
    for (final e in headers.entries) e.key.toLowerCase(): e.value.trim(),
    'x-amz-date': amzDate,
    if (signContentSha256) 'x-amz-content-sha256': payloadHash,
  };
  final names = all.keys.toList()..sort();
  final signedHeaders = names.join(';');
  final canonicalRequest = [
    method,
    uri.path.split('/').map(_encodeSegment).join('/'),
    '',
    for (final n in names) '$n:${all[n]}',
    '',
    signedHeaders,
    payloadHash,
  ].join('\n');

  final scope = '$day/$region/$service/aws4_request';
  final stringToSign = [
    'AWS4-HMAC-SHA256',
    amzDate,
    scope,
    sha256.convert(utf8.encode(canonicalRequest)).toString(),
  ].join('\n');

  List<int> hmac(List<int> key, String data) =>
      Hmac(sha256, key).convert(utf8.encode(data)).bytes;
  var key = hmac(utf8.encode('AWS4$secretAccessKey'), day);
  key = hmac(key, region);
  key = hmac(key, service);
  key = hmac(key, 'aws4_request');
  final signature = Hmac(
    sha256,
    key,
  ).convert(utf8.encode(stringToSign)).toString();

  return {
    ...all,
    'authorization':
        'AWS4-HMAC-SHA256 Credential=$accessKeyId/$scope, '
        'SignedHeaders=$signedHeaders, Signature=$signature',
  }..remove('host');
}

/// Encodage d'un segment de chemin pour la requête canonique S3 (RFC 3986,
/// seuls `A-Za-z0-9-._~` restent tels quels).
String _encodeSegment(String segment) {
  final decoded = Uri.decodeComponent(segment);
  final out = StringBuffer();
  for (final byte in utf8.encode(decoded)) {
    final c = String.fromCharCode(byte);
    if (RegExp(r'[A-Za-z0-9\-._~]').hasMatch(c)) {
      out.write(c);
    } else {
      out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return out.toString();
}
