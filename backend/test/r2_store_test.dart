import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:vote_job/vote_job.dart';

const _internalError =
    '<?xml version="1.0" encoding="UTF-8"?><Error><Code>InternalError</Code>'
    '<Message>We encountered an internal error. Please try again.</Message>'
    '</Error>';

R2Store _store(http.Client client) => R2Store(
  accountId: 'compte',
  bucket: 'seau',
  accessKeyId: 'cle',
  secretAccessKey: 'secret',
  client: client,
  clock: () => DateTime.utc(2026, 11, 7, 16, 18),
  retryDelays: const [Duration.zero, Duration.zero],
);

void main() {
  test('réessaie un PUT refusé par une erreur 500 de R2', () async {
    final statuses = [500, 500, 200];
    var calls = 0;
    final store = _store(
      MockClient((request) async {
        expect(request.headers['authorization'], isNotNull);
        final status = statuses[calls++];
        return http.Response(status == 200 ? '' : _internalError, status);
      }),
    );

    await store.write('state/dossiers.json', '{}');
    expect(calls, 3);
  });

  test('abandonne après le dernier essai et dit pourquoi', () async {
    var calls = 0;
    final store = _store(
      MockClient((_) async {
        calls++;
        return http.Response(_internalError, 500);
      }),
    );

    await expectLater(
      store.write('state/dossiers.json', '{}'),
      throwsA(
        isA<HttpException>().having(
          (e) => e.message,
          'message',
          allOf(contains('PUT state/dossiers.json'), contains('500')),
        ),
      ),
    );
    expect(calls, 3);
  });

  test('ne réessaie pas une erreur du client (4xx)', () async {
    var calls = 0;
    final store = _store(
      MockClient((_) async {
        calls++;
        return http.Response('AccessDenied', 403);
      }),
    );

    await expectLater(
      store.write('state/dossiers.json', '{}'),
      throwsA(isA<HttpException>()),
    );
    expect(calls, 1);
  });

  test('réessaie une lecture coupée par le réseau', () async {
    var calls = 0;
    final store = _store(
      MockClient((_) async {
        if (calls++ == 0) throw http.ClientException('Connection reset');
        return http.Response('{"ok":true}', 200);
      }),
    );

    expect(await store.read('state/live.json'), '{"ok":true}');
    expect(calls, 2);
  });

  test('un objet absent reste null, sans nouvel essai', () async {
    var calls = 0;
    final store = _store(
      MockClient((_) async {
        calls++;
        return http.Response('', 404);
      }),
    );

    expect(await store.read('state/absent.json'), isNull);
    expect(calls, 1);
  });
}
