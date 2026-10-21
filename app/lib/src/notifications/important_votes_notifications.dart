import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../decision_detail/decision_route.dart';
import '../home_widget/home_widget_sync.dart';
import '../home_widget/widget_link.dart';
import 'push_messaging.dart';

/// Sujet FCM des votes importants (même nom que côté job, voir
/// `backend/lib/src/notifications/notification_pass.dart`).
const importantVotesTopic = 'votes-importants';

const _wantedKey = 'notifications.importantVotes.enabled';
const _askedKey = 'notifications.permissionAsked';

/// Décision visée par une notification : la donnée `decisionId`, sinon le
/// lien `votedujour://decisions/<id>` de la donnée `link`.
String? decisionIdFromNotification(Map<String, Object?> data) {
  final id = data['decisionId'];
  if (id is String && id.isNotEmpty && !id.contains('/')) return id;
  final link = data['link'];
  final uri = link is String ? Uri.tryParse(link) : null;
  return uri == null ? null : decisionIdFromDeepLink(uri);
}

/// Lien d'une notification sans décision (veille d'un vote solennel, #54) :
/// `votedujour://decisions` ouvre la liste ; tout autre lien est ignoré.
bool opensListFromNotification(Map<String, Object?> data) {
  final link = data['link'];
  final uri = link is String ? Uri.tryParse(link) : null;
  return uri != null &&
      uri.scheme == 'votedujour' &&
      uri.host == 'decisions' &&
      uri.pathSegments.every((s) => s.isEmpty);
}

/// Notifications des votes importants (#34) : réglage persistant, demande
/// de l'autorisation après une première consultation d'un détail, abonnement
/// au sujet [importantVotesTopic] et ouverture du détail au tap.
///
/// Le réglage est actif par défaut, mais ne prend effet qu'une fois
/// l'autorisation accordée.
class ImportantVotesNotifications extends ChangeNotifier {
  ImportantVotesNotifications({
    required PushMessaging messaging,
    GlobalKey<NavigatorState>? navigatorKey,
    this.showForegroundBanner = false,
  }) : _messaging = messaging,
       _navigatorKey = navigatorKey ?? homeWidgetNavigatorKey;

  final PushMessaging _messaging;
  final GlobalKey<NavigatorState> _navigatorKey;

  /// Bandeau dans l'app pour une notification reçue au premier plan
  /// (Android ; iOS affiche le bandeau du système).
  final bool showForegroundBanner;

  /// Messager de l'app, pour le bandeau du premier plan.
  final messengerKey = GlobalKey<ScaffoldMessengerState>();

  PushPermission _permission = PushPermission.notDetermined;
  bool _wanted = true;
  bool _asked = false;
  final _subscriptions = <StreamSubscription<PushNotification>>[];

  /// Autorisation du système, telle que lue en dernier.
  PushPermission get permission => _permission;

  /// Notifications reçues : réglage actif et autorisation accordée.
  bool get enabled => _wanted && _permission == PushPermission.granted;

  /// L'utilisateur a refusé l'autorisation : seul le réglage du téléphone
  /// peut la rendre.
  bool get refused => _asked && _permission == PushPermission.denied;

  /// À appeler une fois au démarrage.
  Future<void> start() async {
    _subscriptions
      ..add(_messaging.opened.listen(_openDecision))
      ..add(_messaging.foreground.listen(_showBanner));
    final prefs = await SharedPreferences.getInstance();
    _wanted = prefs.getBool(_wantedKey) ?? true;
    _asked = prefs.getBool(_askedKey) ?? false;
    try {
      _permission = await _messaging.permission();
      final initial = await _messaging.initialNotification();
      if (initial != null) _openDecision(initial);
    } catch (e) {
      debugPrint('ImportantVotesNotifications.start : $e');
    }
    notifyListeners();
    if (enabled) await _sync(subscribe: true);
  }

  /// Relit l'autorisation (elle a pu changer dans les réglages du téléphone)
  /// et abonne l'appareil si les notifications deviennent actives.
  Future<void> refreshPermission() async {
    final wasEnabled = enabled;
    try {
      _permission = await _messaging.permission();
    } catch (e) {
      debugPrint('ImportantVotesNotifications.refreshPermission : $e');
      return;
    }
    notifyListeners();
    if (enabled && !wasEnabled) await _sync(subscribe: true);
  }

  /// Un détail de décision vient d'être consulté : à la première fois,
  /// demande l'autorisation (une seule fois).
  Future<void> decisionViewed() async {
    if (_asked || _permission == PushPermission.granted) return;
    await _requestPermission();
    if (enabled) await _sync(subscribe: true);
  }

  /// Interrupteur du réglage. L'activer demande l'autorisation si elle ne
  /// l'a jamais été.
  Future<void> setEnabled(bool value) async {
    if (value && _permission != PushPermission.granted && !refused) {
      await _requestPermission();
    }
    _wanted = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_wantedKey, value);
    notifyListeners();
    if (enabled) {
      await _sync(subscribe: true);
    } else if (!value) {
      await _sync(subscribe: false);
    }
  }

  Future<void> _requestPermission() async {
    _asked = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_askedKey, true);
    try {
      _permission = await _messaging.requestPermission();
    } catch (e) {
      debugPrint('ImportantVotesNotifications.requestPermission : $e');
    }
    notifyListeners();
  }

  /// Abonnement ou désabonnement ; une erreur (réseau absent…) est
  /// journalisée, l'abonnement est retenté au prochain lancement.
  Future<void> _sync({required bool subscribe}) async {
    try {
      if (subscribe) {
        await _messaging.subscribe(importantVotesTopic);
      } else {
        await _messaging.unsubscribe(importantVotesTopic);
      }
    } catch (e) {
      debugPrint('ImportantVotesNotifications._sync($subscribe) : $e');
    }
  }

  /// Ouvre le détail de la décision de la notification, ou revient à la
  /// liste pour une notification sans décision qui la vise (veille d'un
  /// vote solennel) ; sinon l'app s'ouvre simplement.
  void _openDecision(PushNotification notification) {
    final id = decisionIdFromNotification(notification.data);
    if (id == null && !opensListFromNotification(notification.data)) return;
    unawaited(
      openWidgetLinkWhenReady(
        _navigatorKey,
        Uri(scheme: 'votedujour', host: 'decisions', pathSegments: [?id]),
      ),
    );
  }

  void _showBanner(PushNotification notification) {
    if (!showForegroundBanner) return;
    final messenger = messengerKey.currentState;
    final title = notification.title;
    if (messenger == null || title == null) return;
    final id = decisionIdFromNotification(notification.data);
    messenger.showSnackBar(
      SnackBar(
        content: Text(title),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        action: id == null
            ? null
            : SnackBarAction(
                label: 'Voir',
                onPressed: () => _openDecision(notification),
              ),
      ),
    );
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}

/// Rend [ImportantVotesNotifications] accessible aux écrans (réglage de la
/// page À propos).
class NotificationsScope
    extends InheritedNotifier<ImportantVotesNotifications> {
  const NotificationsScope({
    super.key,
    required ImportantVotesNotifications super.notifier,
    required super.child,
  });

  /// Notifications de l'app, ou `null` si elles ne sont pas disponibles
  /// (tests, web, Firebase absent).
  static ImportantVotesNotifications? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<NotificationsScope>()
      ?.notifier;
}

/// Appelle [onLeaveDecision] quand l'utilisateur quitte un détail de
/// décision (première consultation terminée).
class DecisionViewObserver extends NavigatorObserver {
  DecisionViewObserver(this.onLeaveDecision);

  final VoidCallback onLeaveDecision;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (isDecisionRoute(route.settings.name)) onLeaveDecision();
  }
}
