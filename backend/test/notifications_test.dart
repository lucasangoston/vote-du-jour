import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

/// Décision de test : par défaut, un texte de compromis (CMP) confirmé.
DecisionSummary decision(
  String id, {
  int numero = 100,
  DecisionType type = DecisionType.ensembleTexte,
  DecisionStatus status = DecisionStatus.confirmee,
  VoteResult result = VoteResult.adopte,
  VoteMode voteMode = VoteMode.scrutinPublic,
  DateTime? date,
  String? stage = 'Texte de compromis (CMP)',
  String shortTitle = 'Juges spécialisés',
  PlainSummary? summary,
}) => DecisionSummary(
  id: id,
  numero: voteMode == VoteMode.scrutinPublic ? numero : null,
  voteMode: voteMode,
  type: type,
  status: status,
  result: result,
  date: date ?? DateTime.utc(2026, 10, 15),
  officialTitle: "l'ensemble du projet de loi $shortTitle",
  sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/$numero',
  shortTitle: shortTitle,
  stage: stage,
  summary: summary,
);

Scrutin scrutin(String uid, String code, {int numero = 100}) => Scrutin(
  uid: uid,
  numero: numero,
  date: DateTime.utc(2026, 10, 15),
  titre: "l'ensemble du projet de loi",
  codeTypeVote: code,
  libelleTypeVote: '',
  result: VoteResult.adopte,
  decompte: const Decompte(pour: 1, contre: 0, abstentions: 0, nonVotants: 0),
  dossierRef: null,
  groupVotes: const [],
);

/// Vote solennel à venir de test : projet de loi de finances, séance S1.
UpcomingItem vote(
  String id, {
  required DateTime startsAt,
  UpcomingKind kind = UpcomingKind.voteSolennel,
  String seanceRef = 'S1',
  String? dossierRef = 'DLR1',
}) => UpcomingItem(
  id: id,
  kind: kind,
  startsAt: startsAt,
  seanceRef: seanceRef,
  label: 'Vote solennel sur le projet de loi de finances pour 2027',
  shortTitle: 'Projet de loi de finances pour 2027 (première partie)',
  dossierRef: dossierRef,
);

/// Envoi simulé : garde les messages, échoue pour les décisions de [failFor].
class FakeSender implements PushSender {
  final messages = <PushMessage>[];
  final failFor = <String>{};

  /// Décisions et points annoncés la veille, dans l'ordre d'envoi.
  List<String> get ids => [
    for (final m in messages) (m.data['decisionId'] ?? m.data['upcomingId'])!,
  ];

  @override
  Future<void> send(PushMessage message) async {
    if (failFor.contains(
      message.data['decisionId'] ?? message.data['upcomingId'],
    )) {
      throw const FcmException('HTTP 503');
    }
    messages.add(message);
  }
}

void main() {
  group('isImportantDecision', () {
    test('scrutin solennel, quelle que soit l’étape', () {
      final d = decision('A', stage: "1re lecture à l'AN");
      expect(isImportantDecision(d, codeTypeVote: 'SPS'), isTrue);
      expect(isImportantDecision(d, codeTypeVote: 'SPO'), isFalse);
      expect(isImportantDecision(d), isFalse);
    });

    test('motion de censure, adoptée ou rejetée', () {
      final d = decision(
        'A',
        type: DecisionType.motionDeCensure,
        result: VoteResult.rejete,
        stage: 'Motion de censure',
      );
      expect(isImportantDecision(d), isTrue);
      expect(isImportantDecision(d, codeTypeVote: 'MOC'), isTrue);
    });

    test('lecture définitive ou CMP, adopté ou rejeté', () {
      expect(isImportantDecision(decision('A')), isTrue);
      expect(
        isImportantDecision(
          decision(
            'B',
            stage: "Lecture définitive à l'AN",
            result: VoteResult.rejete,
          ),
        ),
        isTrue,
      );
      expect(
        isImportantDecision(
          decision(
            'C',
            type: DecisionType.rejetPrealable,
            result: VoteResult.rejete,
            stage: 'Motion de rejet préalable, Texte de compromis (CMP)',
          ),
        ),
        isTrue,
      );
    });

    test('autres lectures en scrutin ordinaire : non', () {
      for (final stage in [
        "1re lecture à l'AN",
        "Nouvelle lecture à l'AN",
        "Vote sur l'ensemble du texte",
        null,
      ]) {
        expect(
          isImportantDecision(decision('A', stage: stage), codeTypeVote: 'SPO'),
          isFalse,
          reason: '$stage',
        );
      }
    });

    test('jamais : main levée, résolution, décision provisoire', () {
      expect(
        isImportantDecision(decision('A', voteMode: VoteMode.mainLevee)),
        isFalse,
      );
      expect(
        isImportantDecision(
          decision(
            'B',
            type: DecisionType.resolution,
            stage: 'Résolution (sans valeur de loi)',
          ),
          codeTypeVote: 'SPS',
        ),
        isFalse,
      );
      expect(
        isImportantDecision(
          decision('C', status: DecisionStatus.provisoire),
          codeTypeVote: 'SPS',
        ),
        isFalse,
      );
    });
  });

  group('notificationFor', () {
    test('titre, explication, lien profond, son par défaut', () {
      final d = decision(
        'VTANR5L17V7946',
        summary: const PlainSummary(
          title: 'Des juges spécialisés pour les violences intrafamiliales',
          explanation: 'Le texte crée des pôles spécialisés.',
          promptVersion: 1,
        ),
      );
      final message = notificationFor(d);
      expect(message.topic, 'votes-importants');
      expect(
        message.title,
        'Adopté : Des juges spécialisés pour les violences intrafamiliales',
      );
      expect(message.body, 'Le texte crée des pôles spécialisés.');
      expect(message.toFcmJson(), {
        'message': {
          'topic': 'votes-importants',
          'notification': {
            'title':
                'Adopté : Des juges spécialisés pour les violences '
                'intrafamiliales',
            'body': 'Le texte crée des pôles spécialisés.',
          },
          'data': {
            'decisionId': 'VTANR5L17V7946',
            'link': 'votedujour://decisions/VTANR5L17V7946',
          },
          'android': {
            'notification': {'sound': 'default'},
          },
          'apns': {
            'payload': {
              'aps': {'sound': 'default'},
            },
          },
        },
      });
    });

    test('sans résumé : titre court et étape ; rejet', () {
      final message = notificationFor(
        decision(
          'A',
          result: VoteResult.rejete,
          stage: "Lecture définitive à l'AN",
        ),
      );
      expect(message.title, 'Rejeté : Juges spécialisés');
      expect(message.body, "Lecture définitive à l'AN");
    });

    test('titre trop long raccourci', () {
      final message = notificationFor(
        decision('A', shortTitle: List.filled(60, 'mot').join(' ')),
      );
      expect(message.title.length, lessThanOrEqualTo('Adopté : '.length + 120));
      expect(message.title, endsWith('…'));
    });

    test('le lien profond est celui que lit l’app', () {
      expect(
        decisionDeepLink('L17-VD234087DEC'),
        'votedujour://decisions/L17-VD234087DEC',
      );
    });
  });

  group('runNotificationPass', () {
    late Directory dir;
    late LocalDirectoryStore store;
    late FakeSender sender;
    final now = DateTime.utc(2026, 10, 18, 12);

    setUp(() {
      dir = Directory.systemTemp.createTempSync('notifications_test');
      store = LocalDirectoryStore(dir.path);
      sender = FakeSender();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> publish(
      List<DecisionSummary> decisions, {
      List<Scrutin> scrutins = const [],
    }) async {
      await store.write(
        indexPath,
        jsonEncode(
          DecisionIndex(generatedAt: now, decisions: decisions).toJson(),
        ),
      );
      await ConfirmedSnapshot(
        lastNumero: 9999,
        scrutins: scrutins,
      ).write(store);
    }

    Future<NotificationReport> pass() =>
        runNotificationPass(store: store, sender: sender, clock: () => now);

    Future<Map<String, Object?>> readState() async =>
        jsonDecode((await store.read(notificationsStateKey))!)
            as Map<String, Object?>;

    test(
      'premier passage : l’existant est marqué, rien n’est envoyé',
      () async {
        await publish([
          decision('A'),
          decision('B', stage: "1re lecture à l'AN"),
        ]);
        final report = await pass();
        expect(sender.messages, isEmpty);
        expect(report.initialized, 2);
        expect((await readState())['sent'], {'A': 'initial', 'B': 'initial'});

        // Le passage suivant n'envoie toujours rien pour elles.
        expect((await pass()).sent, isEmpty);
        expect(sender.messages, isEmpty);
      },
    );

    test('une décision n’est jamais notifiée deux fois', () async {
      await publish([]);
      await pass();
      await publish([decision('A', numero: 1)]);
      expect((await pass()).sent, ['A']);
      expect((await pass()).sent, isEmpty);
      expect(sender.ids, ['A']);
      expect(((await readState())['sent'] as Map)['A'], now.toIso8601String());
    });

    test('solennel repéré grâce à l’instantané des scrutins', () async {
      await publish([]);
      await pass();
      await publish(
        [
          decision('S', numero: 1, stage: "1re lecture à l'AN"),
          decision('O', numero: 2, stage: "1re lecture à l'AN"),
        ],
        scrutins: [
          scrutin('S', 'SPS', numero: 1),
          scrutin('O', 'SPO', numero: 2),
        ],
      );
      expect((await pass()).sent, ['S']);
    });

    test('plafond de 3 envois, les plus anciens d’abord', () async {
      await publish([]);
      await pass();
      await publish([
        for (var i = 5; i >= 1; i--)
          decision('D$i', numero: i, date: DateTime.utc(2026, 10, 12 + i)),
      ]);
      final first = await pass();
      expect(first.sent, ['D1', 'D2', 'D3']);
      expect(first.deferred, 2);
      expect(first.toString(), contains('2 reportées'));
      final second = await pass();
      expect(second.sent, ['D4', 'D5']);
      expect(second.deferred, 0);
      expect(sender.ids, ['D1', 'D2', 'D3', 'D4', 'D5']);
    });

    test('provisoire : notifiée seulement à la confirmation', () async {
      await publish([]);
      await pass();
      await publish([decision('A', status: DecisionStatus.provisoire)]);
      expect((await pass()).sent, isEmpty);
      await publish([decision('A')]);
      expect((await pass()).sent, ['A']);
    });

    test('échec d’envoi : retenté au passage suivant', () async {
      await publish([]);
      await pass();
      await publish([decision('A', numero: 1), decision('B', numero: 2)]);
      sender.failFor.add('A');
      final report = await pass();
      expect(report.sent, ['B']);
      expect(report.warnings.single, contains('A'));
      sender.failFor.clear();
      expect((await pass()).sent, ['A']);
    });

    test('décision trop ancienne : pas de notification', () async {
      await publish([]);
      await pass();
      await publish([decision('A', date: DateTime.utc(2026, 10, 1))]);
      expect((await pass()).sent, isEmpty);
    });

    test('mémoire illisible : réinitialisée sans envoi', () async {
      await publish([decision('A')]);
      await store.write(notificationsStateKey, '{oups');
      final report = await pass();
      expect(sender.messages, isEmpty);
      expect(report.initialized, 1);
      expect(report.warnings.single, contains('illisible'));
    });
  });

  group('annonce de la veille d’un vote solennel (#54)', () {
    // Heure d'été jusqu'au 25 octobre 2026 : Paris = UTC+2.
    final tomorrow15h = DateTime.utc(2026, 10, 21, 13);

    test('message : titre, heure de Paris réelle, lien vers la liste', () {
      final message = eveNotificationFor(
        vote('P1', startsAt: tomorrow15h),
        topic: importantVotesTopic,
      );
      expect(message.topic, 'votes-importants');
      expect(message.title, 'Vote solennel demain');
      expect(
        message.body,
        'À partir de 15h : Projet de loi de finances pour 2027 '
        '(première partie)',
      );
      expect(message.data, {
        'upcomingId': 'P1',
        'link': 'votedujour://decisions',
      });
      // Heure d'hiver, minutes.
      expect(
        eveNotificationFor(
          vote('P2', startsAt: DateTime.utc(2026, 11, 3, 14, 30)),
          topic: importantVotesTopic,
        ).body,
        startsWith('À partir de 15h30 : '),
      );
    });

    test('le soir de la veille seulement (18h–23h59, heure de Paris)', () {
      final v = vote('P1', startsAt: tomorrow15h);
      bool due(DateTime now) => isEveNotificationDue(v, now);
      expect(due(DateTime.utc(2026, 10, 20, 15, 59)), isFalse); // 17h59
      expect(due(DateTime.utc(2026, 10, 20, 16)), isTrue); // 18h
      expect(due(DateTime.utc(2026, 10, 20, 21, 59)), isTrue); // 23h59
      expect(due(DateTime.utc(2026, 10, 20, 22)), isFalse); // 0h, le jour même
      expect(due(DateTime.utc(2026, 10, 21, 16)), isFalse); // après le vote
      expect(due(DateTime.utc(2026, 10, 19, 18)), isFalse); // l'avant-veille
      expect(
        isEveNotificationDue(
          vote('D', startsAt: tomorrow15h, kind: UpcomingKind.discussion),
          DateTime.utc(2026, 10, 20, 18),
        ),
        isFalse,
      );
    });

    group('runNotificationPass', () {
      late Directory dir;
      late LocalDirectoryStore store;
      late FakeSender sender;
      var now = DateTime.utc(2026, 10, 20, 18); // 20h à Paris

      setUp(() {
        dir = Directory.systemTemp.createTempSync('eve_notifications_test');
        store = LocalDirectoryStore(dir.path);
        sender = FakeSender();
        now = DateTime.utc(2026, 10, 20, 18);
      });
      tearDown(() => dir.deleteSync(recursive: true));

      Future<void> publish(
        List<UpcomingItem> upcoming, {
        List<DecisionSummary> decisions = const [],
      }) async {
        await store.write(
          indexPath,
          jsonEncode(
            DecisionIndex(
              generatedAt: now,
              decisions: decisions,
              upcoming: upcoming,
            ).toJson(),
          ),
        );
        await ConfirmedSnapshot(lastNumero: 9999, scrutins: []).write(store);
      }

      Future<NotificationReport> pass({bool agendaUpToDate = true}) =>
          runNotificationPass(
            store: store,
            sender: sender,
            clock: () => now,
            agendaUpToDate: agendaUpToDate,
          );

      Future<Map<String, Object?>> readState() async =>
          jsonDecode((await store.read(notificationsStateKey))!)
              as Map<String, Object?>;

      /// Mémoire déjà en service, sans rien à notifier.
      Future<void> initialized() async {
        await publish([]);
        await pass();
      }

      test(
        'la veille au soir seulement, pour les votes du lendemain',
        () async {
          await initialized();
          await publish([
            vote('P1', startsAt: tomorrow15h),
            vote(
              'P2',
              startsAt: DateTime.utc(2026, 10, 22, 13),
              seanceRef: 'S2',
              dossierRef: 'DLR2',
            ),
            vote(
              'P3',
              startsAt: tomorrow15h,
              kind: UpcomingKind.discussion,
              dossierRef: 'DLR3',
            ),
          ]);
          now = DateTime.utc(2026, 10, 20, 14); // 16h
          expect((await pass()).eveSent, isEmpty);
          now = DateTime.utc(2026, 10, 20, 18); // 20h
          final report = await pass();
          expect(report.eveSent, ['P1']);
          expect(report.toString(), contains('1 annonces de la veille (P1)'));
          expect(sender.messages.single.title, 'Vote solennel demain');
          expect((await readState())['eve'], {
            'S1 DLR1': now.toIso8601String(),
          });
        },
      );

      test('pas de doublon, même republié sous un autre identifiant', () async {
        await initialized();
        await publish([vote('P1', startsAt: tomorrow15h)]);
        expect((await pass()).eveSent, ['P1']);
        now = DateTime.utc(2026, 10, 20, 21); // 23h
        expect((await pass()).eveSent, isEmpty);
        await publish([vote('P1bis', startsAt: tomorrow15h)]);
        expect((await pass()).eveSent, isEmpty);
        expect(sender.ids, ['P1']);
      });

      test('point supprimé ou reporté : pas d’annonce', () async {
        await initialized();
        // Supprimé : le passage de l'agenda l'a retiré du bloc.
        await publish([]);
        expect((await pass()).eveSent, isEmpty);
        // Reporté au surlendemain, dans une autre séance.
        await publish([
          vote('P1', startsAt: DateTime.utc(2026, 10, 22, 13), seanceRef: 'S2'),
        ]);
        expect((await pass()).eveSent, isEmpty);
        // Annoncé la veille de sa nouvelle date.
        now = DateTime.utc(2026, 10, 21, 18);
        expect((await pass()).eveSent, ['P1']);
        expect(sender.ids, ['P1']);
      });

      test('agenda non relu à ce passage : annonce reportée', () async {
        await initialized();
        await publish([vote('P1', startsAt: tomorrow15h)]);
        final report = await pass(agendaUpToDate: false);
        expect(report.eveSent, isEmpty);
        expect(report.warnings.single, contains('agenda non relu'));
        expect((await pass()).eveSent, ['P1']);
      });

      test('plafond commun avec les décisions, annonces d’abord', () async {
        await initialized();
        await publish(
          [
            vote('P1', startsAt: tomorrow15h),
            vote('P2', startsAt: tomorrow15h, dossierRef: 'DLR2'),
          ],
          decisions: [
            decision('A', numero: 1, date: DateTime.utc(2026, 10, 19)),
            decision('B', numero: 2, date: DateTime.utc(2026, 10, 19)),
          ],
        );
        final first = await pass();
        expect(first.eveSent, ['P1', 'P2']);
        expect(first.sent, ['A']);
        expect(first.deferred, 1);
        final second = await pass();
        expect(second.eveSent, isEmpty);
        expect(second.sent, ['B']);
        expect(sender.ids, ['P1', 'P2', 'A', 'B']);
      });

      test('échec d’envoi : retenté au passage suivant', () async {
        await initialized();
        await publish([vote('P1', startsAt: tomorrow15h)]);
        sender.failFor.add('P1');
        final report = await pass();
        expect(report.eveSent, isEmpty);
        expect(report.warnings.single, contains('P1'));
        sender.failFor.clear();
        expect((await pass()).eveSent, ['P1']);
      });

      test('premier passage : rien n’est envoyé, points marqués', () async {
        await publish(
          [vote('P1', startsAt: tomorrow15h)],
          decisions: [decision('A')],
        );
        final report = await pass();
        expect(sender.messages, isEmpty);
        expect(report.initialized, 2);
        expect((await readState())['eve'], {'S1 DLR1': 'initial'});
        expect((await pass()).eveSent, isEmpty);
        expect(sender.messages, isEmpty);
      });

      test('mémoire d’avant #54 (sans « eve ») : relue sans perte', () async {
        await publish([vote('P1', startsAt: tomorrow15h)]);
        await store.write(
          notificationsStateKey,
          jsonEncode({
            'version': 1,
            'initializedAt': '2026-10-18T12:00:00.000Z',
            'sent': {'A': 'initial'},
          }),
        );
        final report = await pass();
        expect(report.warnings, isEmpty);
        expect(report.eveSent, ['P1']);
        expect((await readState())['sent'], {'A': 'initial'});
      });

      test('annonces oubliées après 30 jours', () async {
        await initialized();
        await publish([vote('P1', startsAt: tomorrow15h)]);
        await pass();
        now = now.add(const Duration(days: 31));
        await publish([]);
        await pass();
        expect((await readState())['eve'], isEmpty);
      });
    });
  });

  group('RS256 et FCM', () {
    late Directory dir;
    late String pkcs8Pem;
    late String publicKeyPath;

    setUpAll(() async {
      dir = Directory.systemTemp.createTempSync('rs256_test');
      // Clé générée pour le test, jamais enregistrée.
      final keyPath = '${dir.path}/key.pem';
      publicKeyPath = '${dir.path}/pub.pem';
      await _run('openssl', [
        'genpkey',
        '-algorithm',
        'RSA',
        '-pkeyopt',
        'rsa_keygen_bits:2048',
        '-out',
        keyPath,
      ]);
      await _run('openssl', [
        'pkey',
        '-in',
        keyPath,
        '-pubout',
        '-out',
        publicKeyPath,
      ]);
      pkcs8Pem = File(keyPath).readAsStringSync();
    });
    tearDownAll(() => dir.deleteSync(recursive: true));

    Future<bool> opensslVerifies(
      String signingInput,
      List<int> signature,
    ) async {
      final data = File('${dir.path}/data')..writeAsStringSync(signingInput);
      final sig = File('${dir.path}/sig')..writeAsBytesSync(signature);
      final result = await Process.run('openssl', [
        'dgst',
        '-sha256',
        '-verify',
        publicKeyPath,
        '-signature',
        sig.path,
        data.path,
      ]);
      return result.exitCode == 0;
    }

    test('JWT RS256 vérifié par OpenSSL', () async {
      final jwt = signJwtRs256(
        claims: {'iss': 'a@b.iam.gserviceaccount.com', 'iat': 1},
        key: RsaPrivateKey.fromPem(pkcs8Pem),
        keyId: 'kid-1',
      );
      final parts = jwt.split('.');
      expect(parts, hasLength(3));
      expect(_decodePart(parts[0]), {
        'alg': 'RS256',
        'typ': 'JWT',
        'kid': 'kid-1',
      });
      final signature = base64Url.decode(base64Url.normalize(parts[2]));
      expect(signature, hasLength(256));
      expect(
        await opensslVerifies('${parts[0]}.${parts[1]}', signature),
        isTrue,
      );
      expect(await opensslVerifies('${parts[0]}.e30', signature), isFalse);
    });

    test('clé PKCS#1 (BEGIN RSA PRIVATE KEY) acceptée', () async {
      final result = await Process.run('openssl', [
        'rsa',
        '-in',
        '${dir.path}/key.pem',
        '-traditional',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final pkcs1 = result.stdout as String;
      expect(pkcs1, contains('BEGIN RSA PRIVATE KEY'));
      final a = RsaPrivateKey.fromPem(pkcs1);
      final b = RsaPrivateKey.fromPem(pkcs8Pem);
      expect(a.modulus, b.modulus);
      expect(a.privateExponent, b.privateExponent);
    });

    test('clé illisible : FormatException', () {
      expect(() => RsaPrivateKey.fromPem('pas une clé'), throwsFormatException);
      expect(
        () => RsaPrivateKey.fromPem(
          '-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----',
        ),
        throwsFormatException,
      );
    });

    String serviceAccountJson() => jsonEncode({
      'type': 'service_account',
      'project_id': 'vote-du-jour-test',
      'private_key_id': 'kid-1',
      'private_key': pkcs8Pem,
      'client_email': 'fcm@vote-du-jour-test.iam.gserviceaccount.com',
      'token_uri': 'https://oauth2.googleapis.com/token',
    });

    test('compte de service incomplet : FormatException', () {
      expect(() => ServiceAccount.fromJson('{'), throwsFormatException);
      expect(
        () => ServiceAccount.fromJson(jsonEncode({'project_id': 'x'})),
        throwsFormatException,
      );
    });

    test('jeton OAuth2 obtenu une fois, puis envois au sujet', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.host == 'oauth2.googleapis.com') {
          return http.Response(
            jsonEncode({'access_token': 'ya29.test', 'expires_in': 3599}),
            200,
          );
        }
        return http.Response('{"name":"projects/x/messages/1"}', 200);
      });
      final now = DateTime.utc(2026, 10, 18, 12);
      final fcm = FcmClient(
        account: ServiceAccount.fromJson(serviceAccountJson()),
        client: client,
        clock: () => now,
      );
      final message = notificationFor(decision('A'));
      await fcm.send(message);
      await fcm.send(message);

      expect(requests, hasLength(3));
      final token = requests[0];
      expect(token.url.toString(), 'https://oauth2.googleapis.com/token');
      expect(
        token.bodyFields['grant_type'],
        'urn:ietf:params:oauth:grant-type:jwt-bearer',
      );
      final assertion = token.bodyFields['assertion']!.split('.');
      final iat = now.millisecondsSinceEpoch ~/ 1000;
      expect(_decodePart(assertion[1]), {
        'iss': 'fcm@vote-du-jour-test.iam.gserviceaccount.com',
        'scope': 'https://www.googleapis.com/auth/firebase.messaging',
        'aud': 'https://oauth2.googleapis.com/token',
        'iat': iat,
        'exp': iat + 3600,
      });
      expect(
        await opensslVerifies(
          '${assertion[0]}.${assertion[1]}',
          base64Url.decode(base64Url.normalize(assertion[2])),
        ),
        isTrue,
      );

      for (final send in requests.skip(1)) {
        expect(
          send.url.toString(),
          'https://fcm.googleapis.com/v1/projects/vote-du-jour-test/messages:send',
        );
        expect(send.headers['authorization'], 'Bearer ya29.test');
        expect(jsonDecode(send.body), message.toFcmJson());
      }
    });

    test('envoi refusé : FcmException', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'oauth2.googleapis.com') {
          return http.Response('{"access_token":"t"}', 200);
        }
        return http.Response('{"error":{"code":404}}', 404);
      });
      final fcm = FcmClient(
        account: ServiceAccount.fromJson(serviceAccountJson()),
        client: client,
      );
      expect(
        () => fcm.send(notificationFor(decision('A'))),
        throwsA(isA<FcmException>()),
      );
    });

    test('jeton refusé : FcmException, retenté à l’envoi suivant', () async {
      var tokenCalls = 0;
      final client = MockClient((request) async {
        if (request.url.host == 'oauth2.googleapis.com') {
          tokenCalls++;
          return tokenCalls == 1
              ? http.Response('{"error":"invalid_grant"}', 400)
              : http.Response('{"access_token":"t"}', 200);
        }
        return http.Response('{}', 200);
      });
      final fcm = FcmClient(
        account: ServiceAccount.fromJson(serviceAccountJson()),
        client: client,
      );
      final message = notificationFor(decision('A'));
      await expectLater(fcm.send(message), throwsA(isA<FcmException>()));
      await fcm.send(message);
      expect(tokenCalls, 2);
    });
  });
}

Future<void> _run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw StateError('$executable ${arguments.join(' ')} : ${result.stderr}');
  }
}

Object? _decodePart(String part) =>
    jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(part))));
