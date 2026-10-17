import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:vote_contract/vote_contract.dart';

import '../decisions_repository.dart';
import 'widget_snapshot.dart';

/// Groupe d'apps partagé entre l'app iOS et l'extension WidgetKit.
const appGroupId = 'group.com.lucasangoston.votedujour';

/// `kind` du widget WidgetKit (voir `ios/DecisionWidget`).
const _iOSWidgetKind = 'DecisionWidget';

/// Récepteur Glance du widget Android.
const _androidWidgetReceiver =
    'com.lucasangoston.votedujour.widget.DecisionWidgetReceiver';

/// Navigateur de l'app, pour revenir à la liste quand on tape sur le widget
/// alors que l'app est déjà ouverte sur un autre écran.
final homeWidgetNavigatorKey = GlobalKey<NavigatorState>();

/// Pont entre l'app et les widgets natifs : écrit l'instantané partagé et
/// ramène l'app sur la liste quand l'utilisateur tape sur un widget.
///
/// Sans effet sur le web et les plateformes sans widget.
class HomeWidgetSync {
  HomeWidgetSync({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  StreamSubscription<Uri?>? _taps;

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// À appeler une fois au démarrage, après
  /// `WidgetsFlutterBinding.ensureInitialized()`.
  Future<void> start() async {
    if (!_supported) return;
    try {
      await HomeWidget.setAppGroupId(appGroupId);
      // Le lancement à froid depuis le widget ouvre déjà l'app sur la liste ;
      // seuls les taps app ouverte demandent de revenir à l'écran d'accueil.
      _taps = HomeWidget.widgetClicked.listen((_) => _showList());
    } catch (e) {
      debugPrint('HomeWidgetSync.start : $e');
    }
  }

  /// Écrit l'instantané des dernières décisions et demande aux widgets de se
  /// redessiner. Une erreur est journalisée, jamais remontée : le widget
  /// garde alors son instantané précédent.
  Future<void> publish(DecisionIndex index) async {
    if (!_supported) return;
    final snapshot = WidgetSnapshot.fromIndex(index, savedAt: _clock());
    try {
      await HomeWidget.saveWidgetData<String>(
        WidgetSnapshot.storageKey,
        jsonEncode(snapshot.toJson()),
      );
      await HomeWidget.updateWidget(
        iOSName: _iOSWidgetKind,
        qualifiedAndroidName: _androidWidgetReceiver,
      );
    } catch (e) {
      debugPrint('HomeWidgetSync.publish : $e');
    }
  }

  void _showList() {
    homeWidgetNavigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  Future<void> dispose() async => _taps?.cancel();
}

/// [DecisionsRepository] qui met à jour les widgets après chaque chargement
/// réussi de l'index.
class WidgetSyncingRepository extends DecisionsRepository {
  WidgetSyncingRepository({
    required super.baseUrl,
    super.client,
    required HomeWidgetSync sync,
  }) : _sync = sync;

  final HomeWidgetSync _sync;

  @override
  Future<DecisionIndex> fetchLatest() async {
    final index = await super.fetchLatest();
    unawaited(_sync.publish(index));
    return index;
  }
}
