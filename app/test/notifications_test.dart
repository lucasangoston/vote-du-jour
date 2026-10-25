import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:votedujour/main.dart';
import 'package:votedujour/src/about_page.dart';
import 'package:votedujour/src/decision_detail/decision_detail_page.dart';
import 'package:votedujour/src/decision_detail/decision_detail_repository.dart';
import 'package:votedujour/src/decision_detail/decision_route.dart';
import 'package:votedujour/src/decisions_repository.dart';
import 'package:votedujour/src/notifications/important_votes_notifications.dart';
import 'package:votedujour/src/notifications/push_messaging.dart';

/// Faux Firebase Cloud Messaging : autorisation programmable, journal des
/// abonnements et notifications injectées à la main.
class FakePushMessaging implements PushMessaging {
  FakePushMessaging({
    this.current = PushPermission.notDetermined,
    this.answer = PushPermission.granted,
    this.initial,
  });

  /// Autorisation actuelle.
  PushPermission current;

  /// Réponse de l'utilisateur à la demande d'autorisation.
  PushPermission answer;

  PushNotification? initial;
  int requests = 0;
  final topics = <String>{};
  final log = <String>[];
  final openedController = StreamController<PushNotification>.broadcast();
  final foregroundController = StreamController<PushNotification>.broadcast();

  @override
  Future<PushPermission> permission() async => current;

  @override
  Future<PushPermission> requestPermission() async {
    requests++;
    return current = answer;
  }

  @override
  Future<void> subscribe(String topic) async {
    topics.add(topic);
    log.add('subscribe $topic');
  }

  @override
  Future<void> unsubscribe(String topic) async {
    topics.remove(topic);
    log.add('unsubscribe $topic');
  }

  @override
  Future<PushNotification?> initialNotification() async => initial;

  @override
  Stream<PushNotification> get opened => openedController.stream;

  @override
  Stream<PushNotification> get foreground => foregroundController.stream;
}

final _summary = DecisionSummary(
  id: 'VTANR5L17V6346',
  numero: 6346,
  type: DecisionType.ensembleTexte,
  status: DecisionStatus.confirmee,
  result: VoteResult.adopte,
  date: DateTime.utc(2026, 4, 9),
  officialTitle: "l'ensemble du projet de loi exemple.",
  sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/6346',
  shortTitle: 'Restitution de biens culturels',
);

MockClient _server() => MockClient((request) async {
  final body = switch (request.url.path) {
    '/v1/latest.json' => DecisionIndex(
      generatedAt: DateTime.utc(2026, 10, 17),
      decisions: [_summary],
    ).toJson(),
    '/v1/decisions/VTANR5L17V6346.json' => DecisionDetail(
      decision: _summary,
    ).toJson(),
    _ => null,
  };
  if (body == null) return http.Response('', 404);
  return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
});

const _notification = PushNotification(
  title: 'Adopté : Restitution de biens culturels',
  body: 'Le texte est adopté.',
  data: {
    'decisionId': 'VTANR5L17V6346',
    'link': 'votedujour://decisions/VTANR5L17V6346',
  },
);

Future<ImportantVotesNotifications> _pumpApp(
  WidgetTester tester,
  FakePushMessaging messaging, {
  bool showForegroundBanner = false,
}) async {
  final client = _server();
  final notifications = ImportantVotesNotifications(
    messaging: messaging,
    showForegroundBanner: showForegroundBanner,
  );
  await tester.pumpWidget(
    VoteDuJourApp(
      repository: DecisionsRepository(
        baseUrl: 'https://example.test',
        client: client,
      ),
      detailRepository: DecisionDetailRepository(
        baseUrl: 'https://example.test',
        client: client,
      ),
      notifications: notifications,
    ),
  );
  await tester.runAsync(notifications.start);
  await tester.pumpAndSettle();
  return notifications;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('decisionIdFromNotification', () {
    test('lit decisionId, sinon le lien', () {
      expect(decisionIdFromNotification(_notification.data), 'VTANR5L17V6346');
      expect(
        decisionIdFromNotification({
          'link': 'votedujour://decisions/VTANR5L17V8706',
        }),
        'VTANR5L17V8706',
      );
      expect(decisionIdFromNotification({}), isNull);
      expect(decisionIdFromNotification({'decisionId': 'a/b'}), isNull);
      expect(
        decisionIdFromNotification({'link': 'https://example.test/x'}),
        isNull,
      );
    });
  });

  group('opensListFromNotification', () {
    test('lien vers la liste seulement', () {
      const eve = {'upcomingId': 'P1', 'link': 'votedujour://decisions'};
      expect(decisionIdFromNotification(eve), isNull);
      expect(opensListFromNotification(eve), isTrue);
      expect(opensListFromNotification(_notification.data), isFalse);
      expect(opensListFromNotification({}), isFalse);
      expect(
        opensListFromNotification({'link': 'https://example.test/'}),
        isFalse,
      );
    });
  });

  group('réglage', () {
    test('autorisation accordée : abonné par défaut au lancement', () async {
      final messaging = FakePushMessaging(current: PushPermission.granted);
      final notifications = ImportantVotesNotifications(messaging: messaging);
      await notifications.start();
      expect(notifications.enabled, isTrue);
      expect(messaging.topics, {importantVotesTopic});
      expect(messaging.requests, 0);
    });

    test('pas d\'abonnement sans autorisation', () async {
      final messaging = FakePushMessaging();
      final notifications = ImportantVotesNotifications(messaging: messaging);
      await notifications.start();
      expect(notifications.enabled, isFalse);
      expect(messaging.log, isEmpty);
      expect(messaging.requests, 0, reason: 'jamais demandée au lancement');
    });

    test('couper le réglage désabonne, et le choix est retenu', () async {
      final messaging = FakePushMessaging(current: PushPermission.granted);
      final notifications = ImportantVotesNotifications(messaging: messaging);
      await notifications.start();
      await notifications.setEnabled(false);
      expect(notifications.enabled, isFalse);
      expect(messaging.log.last, 'unsubscribe $importantVotesTopic');

      // Lancement suivant : le réglage coupé n'abonne pas.
      final next = FakePushMessaging(current: PushPermission.granted);
      final restarted = ImportantVotesNotifications(messaging: next);
      await restarted.start();
      expect(restarted.enabled, isFalse);
      expect(next.log, isEmpty);

      await restarted.setEnabled(true);
      expect(restarted.enabled, isTrue);
      expect(next.log, ['subscribe $importantVotesTopic']);
    });

    test('activer le réglage demande l\'autorisation si besoin', () async {
      final messaging = FakePushMessaging();
      final notifications = ImportantVotesNotifications(messaging: messaging);
      await notifications.start();
      await notifications.setEnabled(true);
      expect(messaging.requests, 1);
      expect(notifications.enabled, isTrue);
      expect(messaging.topics, {importantVotesTopic});
    });

    test('autorisation rendue dans les réglages du téléphone', () async {
      final messaging = FakePushMessaging(answer: PushPermission.denied);
      final notifications = ImportantVotesNotifications(messaging: messaging);
      await notifications.start();
      await notifications.decisionViewed();
      expect(notifications.refused, isTrue);

      messaging.current = PushPermission.granted;
      await notifications.refreshPermission();
      expect(notifications.refused, isFalse);
      expect(notifications.enabled, isTrue);
      expect(messaging.topics, {importantVotesTopic});
    });
  });

  group('demande d\'autorisation', () {
    test('une seule fois, après une consultation', () async {
      final messaging = FakePushMessaging(answer: PushPermission.denied);
      final notifications = ImportantVotesNotifications(messaging: messaging);
      await notifications.start();
      await notifications.decisionViewed();
      await notifications.decisionViewed();
      expect(messaging.requests, 1);
      expect(notifications.refused, isTrue);
      expect(messaging.log, isEmpty);

      // Ni au lancement suivant.
      final restarted = ImportantVotesNotifications(messaging: messaging);
      await restarted.start();
      await restarted.decisionViewed();
      expect(messaging.requests, 1);
      expect(restarted.refused, isTrue);
    });

    testWidgets('demandée en quittant le premier détail consulté', (
      tester,
    ) async {
      final messaging = FakePushMessaging();
      final notifications = await _pumpApp(tester, messaging);
      expect(messaging.requests, 0, reason: 'pas au lancement');

      await tester.tap(find.text('Restitution de biens culturels'));
      await tester.pumpAndSettle();
      expect(find.byType(DecisionDetailPage), findsOneWidget);
      expect(messaging.requests, 0);

      await tester.runAsync(() async {
        _popDetail(tester);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(messaging.requests, 1);
      expect(notifications.enabled, isTrue);
      expect(messaging.topics, {importantVotesTopic});
    });
  });

  group('tap sur la notification', () {
    testWidgets('app ouverte ou en arrière-plan : ouvre le détail', (
      tester,
    ) async {
      final messaging = FakePushMessaging(current: PushPermission.granted);
      await _pumpApp(tester, messaging);
      expect(find.byType(DecisionDetailPage), findsNothing);

      messaging.openedController.add(_notification);
      await tester.pumpAndSettle();
      final page = tester.widget<DecisionDetailPage>(
        find.byType(DecisionDetailPage),
      );
      expect(page.id, 'VTANR5L17V6346');
      expect(
        ModalRoute.of(
          tester.element(find.byType(DecisionDetailPage)),
        )!.settings.name,
        decisionRouteName('VTANR5L17V6346'),
      );
    });

    testWidgets('veille d\'un vote solennel : revient à la liste', (
      tester,
    ) async {
      final messaging = FakePushMessaging(current: PushPermission.granted);
      await _pumpApp(tester, messaging);
      messaging.openedController.add(_notification);
      await tester.pumpAndSettle();
      expect(find.byType(DecisionDetailPage), findsOneWidget);

      messaging.openedController.add(
        const PushNotification(
          title: 'Vote solennel demain',
          body: 'À partir de 15h : Projet de loi de finances pour 2027',
          data: {'upcomingId': 'P1', 'link': 'votedujour://decisions'},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DecisionDetailPage), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('app fermée : ouvre le détail au lancement', (tester) async {
      final messaging = FakePushMessaging(
        current: PushPermission.granted,
        initial: const PushNotification(
          data: {'link': 'votedujour://decisions/VTANR5L17V6346'},
        ),
      );
      await _pumpApp(tester, messaging);
      expect(
        tester.widget<DecisionDetailPage>(find.byType(DecisionDetailPage)).id,
        'VTANR5L17V6346',
      );
    });

    testWidgets(
      'premier plan : bandeau dans l\'app, « Voir » ouvre le détail',
      (tester) async {
        final messaging = FakePushMessaging(current: PushPermission.granted);
        await _pumpApp(tester, messaging, showForegroundBanner: true);

        messaging.foregroundController.add(_notification);
        await tester.pumpAndSettle();
        expect(
          find.text('Adopté : Restitution de biens culturels'),
          findsOneWidget,
        );
        await tester.tap(find.text('Voir'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<DecisionDetailPage>(find.byType(DecisionDetailPage)).id,
          'VTANR5L17V6346',
        );
      },
    );
  });

  group('page À propos', () {
    Future<void> openAbout(WidgetTester tester) async {
      await tester.tap(find.byTooltip('À propos'));
      await tester.pumpAndSettle();
      expect(find.byType(AboutPage), findsOneWidget);
    }

    testWidgets('interrupteur : coupe et rétablit l\'abonnement', (
      tester,
    ) async {
      final messaging = FakePushMessaging(current: PushPermission.granted);
      await _pumpApp(tester, messaging);
      await openAbout(tester);

      expect(find.text('Notifier les votes solennels'), findsOneWidget);
      final toggle = find.byType(Switch);
      expect(tester.widget<Switch>(toggle).value, isTrue);

      await tester.runAsync(() async {
        await tester.tap(toggle);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(toggle).value, isFalse);
      expect(messaging.log.last, 'unsubscribe $importantVotesTopic');

      await tester.runAsync(() async {
        await tester.tap(toggle);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(toggle).value, isTrue);
      expect(messaging.log.last, 'subscribe $importantVotesTopic');

      // Toute la ligne bascule le réglage.
      await tester.runAsync(() async {
        await tester.tap(find.text('Notifier les votes solennels'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(toggle).value, isFalse);
    });

    testWidgets('autorisation refusée : le réglage l\'indique', (tester) async {
      final messaging = FakePushMessaging(answer: PushPermission.denied);
      final notifications = await _pumpApp(tester, messaging);
      await tester.runAsync(notifications.decisionViewed);
      await openAbout(tester);

      expect(
        find.text('Notifications refusées : activez-les dans les Réglages.'),
        findsOneWidget,
      );
      final toggle = tester.widget<Switch>(find.byType(Switch));
      expect(toggle.value, isFalse);
      expect(toggle.onChanged, isNull);
    });

    testWidgets('absent sans notifications', (tester) async {
      await tester.pumpWidget(
        VoteDuJourApp(
          repository: DecisionsRepository(
            baseUrl: 'https://example.test',
            client: _server(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openAbout(tester);
      expect(find.text('Notifier les votes solennels'), findsNothing);
      // La ligne du widget reste, seule dans son panneau.
      expect(find.text('Ajouter le widget'), findsOneWidget);
    });
  });
}

/// Retour à la liste depuis le détail.
void _popDetail(WidgetTester tester) =>
    Navigator.of(tester.element(find.byType(DecisionDetailPage))).pop();
