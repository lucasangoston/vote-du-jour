import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:vote_contract/vote_contract.dart';

import '../decisions_repository.dart';
import 'widget_link.dart';
import 'widget_snapshot.dart';

/// Groupe d'apps partagé entre l'app iOS et l'extension WidgetKit.
const appGroupId = 'group.com.lucasangoston.votedujour';

/// `kind` du widget WidgetKit (voir `ios/DecisionWidget`), commun aux trois
/// tailles.
const _iOSWidgetKind = 'DecisionWidget';

/// Récepteurs Glance des widgets Android : un par taille (petit, moyen,
/// grand ; voir `DecisionWidget.kt`).
const _androidWidgetReceivers = [
  'com.lucasangoston.votedujour.widget.SmallDecisionWidgetReceiver',
  'com.lucasangoston.votedujour.widget.DecisionWidgetReceiver',
  'com.lucasangoston.votedujour.widget.LargeDecisionWidgetReceiver',
];

/// Navigateur de l'app, pour ouvrir le détail d'une décision (ou revenir à la
/// liste) quand on tape sur le widget.
final homeWidgetNavigatorKey = GlobalKey<NavigatorState>();

/// Pont entre l'app et les widgets natifs : écrit l'instantané partagé et
/// ouvre le détail de la décision (ou la liste) quand l'utilisateur tape sur
/// un widget.
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
      _taps = HomeWidget.widgetClicked.listen(_open);
      // Lancement à froid depuis le widget : ouvrir le détail demandé.
      // Le lien peut aussi arriver par le flux (Android : tâche gardée par le
      // système après la mort du processus) : il n'est ouvert qu'une fois.
      final initial = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (initial != null && initial.hasScheme && initial != _lastOpened) {
        _open(initial);
      }
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
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await HomeWidget.updateWidget(iOSName: _iOSWidgetKind);
      } else {
        for (final receiver in _androidWidgetReceivers) {
          await HomeWidget.updateWidget(qualifiedAndroidName: receiver);
        }
      }
    } catch (e) {
      debugPrint('HomeWidgetSync.publish : $e');
    }
  }

  Uri? _lastOpened;

  /// Ouvre le lien d'un tap, dès que le navigateur existe (le flux peut
  /// livrer un tap avant la première image, au lancement).
  void _open(Uri? uri) {
    _lastOpened = uri;
    unawaited(openWidgetLinkWhenReady(homeWidgetNavigatorKey, uri));
  }

  Future<void> dispose() async => _taps?.cancel();
}

/// [DecisionsRepository] qui met à jour les widgets après chaque chargement
/// réussi de l'index.
class WidgetSyncingRepository extends DecisionsRepository {
  WidgetSyncingRepository({
    required super.baseUrl,
    super.client,
    super.cache,
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
