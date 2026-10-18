import 'package:firebase_messaging/firebase_messaging.dart';

/// Autorisation d'afficher des notifications, accordée par l'utilisateur.
enum PushPermission {
  /// Jamais demandée (ou, sur Android 13+, pas encore accordée).
  notDetermined,
  granted,
  denied,
}

/// Notification reçue ou touchée : titre, corps et données du message.
class PushNotification {
  const PushNotification({this.title, this.body, this.data = const {}});

  final String? title;
  final String? body;
  final Map<String, Object?> data;
}

/// Service de notifications push (Firebase Cloud Messaging en production, un
/// faux dans les tests).
abstract interface class PushMessaging {
  /// Autorisation actuelle, sans rien demander.
  Future<PushPermission> permission();

  /// Demande l'autorisation (boîte de dialogue du système).
  Future<PushPermission> requestPermission();

  Future<void> subscribe(String topic);

  Future<void> unsubscribe(String topic);

  /// Notification touchée qui a lancé l'app (app fermée), ou `null`.
  Future<PushNotification?> initialNotification();

  /// Notifications touchées pendant que l'app tourne (en arrière-plan ou au
  /// premier plan).
  Stream<PushNotification> get opened;

  /// Notifications reçues pendant que l'app est au premier plan.
  Stream<PushNotification> get foreground;
}

/// [PushMessaging] adossé à `firebase_messaging`, après
/// `Firebase.initializeApp()`.
class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging() : _messaging = FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  /// iOS : affiche aussi les notifications reçues au premier plan (bandeau
  /// du système, dont le tap passe par [opened]).
  Future<void> init() =>
      _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

  static PushPermission _map(NotificationSettings settings) =>
      switch (settings.authorizationStatus) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => PushPermission.granted,
        AuthorizationStatus.denied ||
        AuthorizationStatus.deniedPermanently => PushPermission.denied,
        AuthorizationStatus.notDetermined => PushPermission.notDetermined,
      };

  static PushNotification _convert(RemoteMessage message) => PushNotification(
    title: message.notification?.title,
    body: message.notification?.body,
    data: message.data,
  );

  @override
  Future<PushPermission> permission() async =>
      _map(await _messaging.getNotificationSettings());

  @override
  Future<PushPermission> requestPermission() async =>
      _map(await _messaging.requestPermission());

  @override
  Future<void> subscribe(String topic) async {
    // L'inscription auprès de FCM est coupée par défaut (Info.plist,
    // AndroidManifest) : aucun jeton n'est créé tant que l'utilisateur n'a
    // pas activé les notifications.
    await _messaging.setAutoInitEnabled(true);
    await _messaging.subscribeToTopic(topic);
  }

  @override
  Future<void> unsubscribe(String topic) =>
      _messaging.unsubscribeFromTopic(topic);

  @override
  Future<PushNotification?> initialNotification() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : _convert(message);
  }

  @override
  Stream<PushNotification> get opened =>
      FirebaseMessaging.onMessageOpenedApp.map(_convert);

  @override
  Stream<PushNotification> get foreground =>
      FirebaseMessaging.onMessage.map(_convert);
}
