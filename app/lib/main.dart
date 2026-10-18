import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/app_identity.dart';
import 'src/config.dart';
import 'src/decision_detail/decision_detail_repository.dart';
import 'src/decision_detail/decision_route.dart';
import 'src/decision_list_page.dart';
import 'src/decisions_cache.dart';
import 'src/decisions_repository.dart';
import 'src/home_widget/home_widget_sync.dart';
import 'src/home_widget/widget_data_source.dart';
import 'src/notifications/important_votes_notifications.dart';
import 'src/notifications/push_messaging.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final widgetSync = HomeWidgetSync()..start();
  shareDataBaseUrl(dataBaseUrl);
  final notifications = await _startNotifications();
  runApp(
    VoteDuJourApp(
      repository: WidgetSyncingRepository(
        baseUrl: dataBaseUrl,
        cache: FileDecisionsCache(),
        sync: widgetSync,
      ),
      notifications: notifications,
    ),
  );
}

/// Notifications des votes importants (#34), sur iOS et Android seulement ;
/// `null` si Firebase ne démarre pas (l'app fonctionne alors sans).
Future<ImportantVotesNotifications?> _startNotifications() async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.iOS &&
          defaultTargetPlatform != TargetPlatform.android)) {
    return null;
  }
  try {
    await Firebase.initializeApp();
    final messaging = FirebasePushMessaging();
    await messaging.init();
    final notifications = ImportantVotesNotifications(
      messaging: messaging,
      showForegroundBanner: defaultTargetPlatform == TargetPlatform.android,
    );
    notifications.start();
    return notifications;
  } catch (e) {
    debugPrint('Notifications indisponibles : $e');
    return null;
  }
}

class VoteDuJourApp extends StatelessWidget {
  const VoteDuJourApp({
    super.key,
    required this.repository,
    this.detailRepository,
    this.notifications,
  });

  final DecisionsRepository repository;

  /// Fichiers de détail ; par défaut, l'URL publique des données.
  final DecisionDetailRepository? detailRepository;

  /// Notifications des votes importants, si disponibles.
  final ImportantVotesNotifications? notifications;

  @override
  Widget build(BuildContext context) {
    final notifications = this.notifications;
    return MaterialApp(
      title: appName,
      navigatorKey: homeWidgetNavigatorKey,
      scaffoldMessengerKey: notifications?.messengerKey,
      navigatorObservers: [
        if (notifications != null)
          DecisionViewObserver(notifications.decisionViewed),
      ],
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      builder: notifications == null
          ? null
          : (context, child) => NotificationsScope(
              notifier: notifications,
              child: child ?? const SizedBox.shrink(),
            ),
      home: DecisionListPage(repository: repository),
      onGenerateRoute: (settings) =>
          generateDecisionRoute(settings, repository: detailRepository),
    );
  }
}
