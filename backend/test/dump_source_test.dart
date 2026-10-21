import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:vote_job/src/dump_source.dart';

void main() {
  group('HttpDumpSource', () {
    HttpDumpSource source(MockClient client) => HttpDumpSource(
      url: 'https://example.test/Scrutins.json.zip',
      client: client,
      retryDelay: Duration.zero,
    );

    test('retente après une connexion coupée', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          throw http.ClientException('Connection closed while receiving data');
        }
        return http.Response.bytes([1, 2, 3], 200);
      });
      final fetch = await source(client).fetch();
      expect(calls, 2);
      expect(fetch, isA<DumpDownloaded>());
    });

    test('retente après une réponse 503', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return calls == 1 ? http.Response('', 503) : http.Response('', 304);
      });
      expect(await source(client).fetch(), isA<DumpNotModified>());
      expect(calls, 2);
    });

    test('abandonne après trois essais', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        throw http.ClientException('Connection closed');
      });
      await expectLater(
        source(client).fetch(),
        throwsA(isA<http.ClientException>()),
      );
      expect(calls, 3);
    });

    test('ne retente pas une erreur 404', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('', 404);
      });
      await expectLater(source(client).fetch(), throwsA(isA<HttpException>()));
      expect(calls, 1);
    });
  });
}
