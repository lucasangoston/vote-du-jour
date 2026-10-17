import 'package:flutter/material.dart';

import 'src/app_identity.dart';
import 'src/config.dart';
import 'src/decision_list_page.dart';
import 'src/decisions_repository.dart';
import 'src/home_widget/home_widget_sync.dart';
import 'src/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final widgetSync = HomeWidgetSync()..start();
  runApp(
    VoteDuJourApp(
      repository: WidgetSyncingRepository(
        baseUrl: dataBaseUrl,
        sync: widgetSync,
      ),
    ),
  );
}

class VoteDuJourApp extends StatelessWidget {
  const VoteDuJourApp({super.key, required this.repository});

  final DecisionsRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      navigatorKey: homeWidgetNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: DecisionListPage(repository: repository),
    );
  }
}
