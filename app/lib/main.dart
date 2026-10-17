import 'package:flutter/material.dart';

import 'src/app_identity.dart';
import 'src/config.dart';
import 'src/decision_list_page.dart';
import 'src/decisions_repository.dart';
import 'src/theme.dart';

void main() {
  runApp(VoteDuJourApp(repository: DecisionsRepository(baseUrl: dataBaseUrl)));
}

class VoteDuJourApp extends StatelessWidget {
  const VoteDuJourApp({super.key, required this.repository});

  final DecisionsRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: DecisionListPage(repository: repository),
    );
  }
}
