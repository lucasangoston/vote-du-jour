import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'home_widget_sync.dart';

/// Clé de l'URL de base des données dans l'espace partagé avec les widgets.
///
/// Les widgets téléchargent eux-mêmes `v1/latest.json` pour se rafraîchir
/// sans l'app (timeline WidgetKit sur iOS, WorkManager sur Android). Ils
/// lisent l'URL ici, sinon l'URL publique compilée dans le code natif : une
/// app lancée avec `--dart-define=DATA_BASE_URL=…` est ainsi suivie par ses
/// widgets.
const dataBaseUrlStorageKey = 'data_base_url';

/// Partage [baseUrl] avec les widgets natifs. Sans effet hors iOS et Android ;
/// une erreur est journalisée, jamais remontée.
Future<void> shareDataBaseUrl(String baseUrl) async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.iOS &&
          defaultTargetPlatform != TargetPlatform.android)) {
    return;
  }
  try {
    await HomeWidget.setAppGroupId(appGroupId);
    await HomeWidget.saveWidgetData<String>(dataBaseUrlStorageKey, baseUrl);
  } catch (e) {
    debugPrint('shareDataBaseUrl : $e');
  }
}
