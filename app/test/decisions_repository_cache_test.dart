import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:votedujour/src/decisions_cache.dart';
import 'package:votedujour/src/decisions_repository.dart';

DecisionIndex _index(int numero) => DecisionIndex(
  generatedAt: DateTime.utc(2026, 10, 17, 10),
  decisions: [
    DecisionSummary(
      id: 'VTANR5L17V$numero',
      numero: numero,
      type: DecisionType.ensembleTexte,
      status: DecisionStatus.confirmee,
      result: VoteResult.adopte,
      date: DateTime.utc(2026, 10, 16),
      officialTitle: "l'ensemble du projet de loi n° $numero.",
      sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/$numero',
      shortTitle: 'Texte $numero',
    ),
  ],
);

http.Response _ok(DecisionIndex index) =>
    http.Response.bytes(utf8.encode(jsonEncode(index.toJson())), 200);

void main() {
  late Directory dir;
  late FileDecisionsCache cache;
  late http.Response Function() server;

  DecisionsRepository repository() => DecisionsRepository(
    baseUrl: 'https://example.test',
    client: MockClient((_) async => server()),
    cache: cache,
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('decisions_cache_test');
    cache = FileDecisionsCache(directory: () async => dir);
  });

  tearDown(() => dir.delete(recursive: true));

  test('sans cache ni réseau, rien à afficher', () async {
    server = () => throw const SocketException('hors ligne');

    expect(await repository().readCached(), isNull);
    await expectLater(
      repository().fetchLatest(),
      throwsA(isA<SocketException>()),
    );
  });

  test('hors ligne, relit le dernier index téléchargé', () async {
    server = () => _ok(_index(8710));
    await repository().fetchLatest();

    // Nouveau lancement de l'app, sans connexion.
    server = () => throw const SocketException('hors ligne');
    final offline = repository();
    await expectLater(offline.fetchLatest(), throwsA(isA<SocketException>()));
    final cached = await offline.readCached();

    expect(cached!.decisions.single.id, 'VTANR5L17V8710');
    expect(cached.decisions.single.displayTitle, 'Texte 8710');
  });

  test('chaque téléchargement réussi remplace le cache', () async {
    server = () => _ok(_index(8710));
    await repository().fetchLatest();
    server = () => _ok(_index(8711));
    await repository().fetchLatest();

    expect((await repository().readCached())!.decisions.single.numero, 8711);
  });

  test('une réponse en erreur ou illisible ne remplace pas le cache', () async {
    server = () => _ok(_index(8710));
    await repository().fetchLatest();

    server = () => http.Response('panne', 503);
    await expectLater(
      repository().fetchLatest(),
      throwsA(isA<DecisionsUnavailable>()),
    );
    server = () => http.Response('{"schemaVersion": 2}', 200);
    await expectLater(
      repository().fetchLatest(),
      throwsA(isA<UnsupportedSchemaException>()),
    );

    expect((await repository().readCached())!.decisions.single.numero, 8710);
  });

  test('un cache illisible est ignoré', () async {
    await cache.write('{pas du json');
    server = () => throw const SocketException('hors ligne');

    expect(await repository().readCached(), isNull);
  });
}
