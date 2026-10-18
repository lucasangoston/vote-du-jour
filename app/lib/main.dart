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
import 'src/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final widgetSync = HomeWidgetSync()..start();
  shareDataBaseUrl(dataBaseUrl);
  runApp(
    VoteDuJourApp(
      repository: WidgetSyncingRepository(
        baseUrl: dataBaseUrl,
        cache: FileDecisionsCache(),
        sync: widgetSync,
      ),
    ),
  );
}

class VoteDuJourApp extends StatelessWidget {
  const VoteDuJourApp({
    super.key,
    required this.repository,
    this.detailRepository,
  });

  final DecisionsRepository repository;

  /// Fichiers de détail ; par défaut, l'URL publique des données.
  final DecisionDetailRepository? detailRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      navigatorKey: homeWidgetNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: DecisionListPage(repository: repository),
      onGenerateRoute: (settings) =>
          generateDecisionRoute(settings, repository: detailRepository),
    );
  }
}
