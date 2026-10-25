import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/app_identity.dart';
import 'src/appearance.dart';
import 'src/config.dart';
import 'src/decision_detail/decision_detail_repository.dart';
import 'src/decision_detail/decision_route.dart';
import 'src/decisions_cache.dart';
import 'src/decisions_repository.dart';
import 'src/home_page.dart';
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
  // Lu avant le premier écran, pour ne pas l'afficher dans la mauvaise
  // apparence.
  final appearance = await AppearanceSettings.load();
  runApp(
    VoteDuJourApp(
      repository: WidgetSyncingRepository(
        baseUrl: dataBaseUrl,
        cache: FileDecisionsCache(),
        sync: widgetSync,
      ),
      notifications: notifications,
      appearance: appearance,
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

class VoteDuJourApp extends StatefulWidget {
  const VoteDuJourApp({
    super.key,
    required this.repository,
    this.detailRepository,
    this.notifications,
    this.appearance,
  });

  final DecisionsRepository repository;

  /// Fichiers de détail ; par défaut, l'URL publique des données.
  final DecisionDetailRepository? detailRepository;

  /// Notifications des votes importants, si disponibles.
  final ImportantVotesNotifications? notifications;

  /// Réglage d'apparence ; par défaut, Auto.
  final AppearanceSettings? appearance;

  @override
  State<VoteDuJourApp> createState() => _VoteDuJourAppState();
}

class _VoteDuJourAppState extends State<VoteDuJourApp> {
  late final _appearance = widget.appearance ?? AppearanceSettings();

  @override
  void dispose() {
    // Le réglage créé ici appartient à l'app ; celui reçu, à l'appelant.
    if (widget.appearance == null) _appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifications = widget.notifications;
    return ListenableBuilder(
      listenable: _appearance,
      builder: (context, _) => MaterialApp(
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
        themeMode: _appearance.mode,
        builder: (context, child) {
          Widget page = AppearanceScope(
            notifier: _appearance,
            child: child ?? const SizedBox.shrink(),
          );
          if (notifications != null) {
            page = NotificationsScope(notifier: notifications, child: page);
          }
          return page;
        },
        home: HomePage(
          repository: widget.repository,
          detailRepository: widget.detailRepository,
        ),
        onGenerateRoute: (settings) => generateDecisionRoute(
          settings,
          repository: widget.detailRepository,
        ),
      ),
    );
  }
}
