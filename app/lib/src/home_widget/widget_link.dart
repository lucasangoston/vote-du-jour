import 'package:flutter/widgets.dart';

import '../decision_detail/decision_route.dart';

/// Ouvre l'écran demandé par un tap sur un widget : le détail de la décision
/// pour `votedujour://decisions/<id>?homeWidget`, la liste sinon
/// (`votedujour://decisions?homeWidget`). L'app revient d'abord à la liste,
/// pour qu'un retour depuis le détail y mène.
void openWidgetLink(NavigatorState navigator, Uri? uri) {
  navigator.popUntil((route) => route.isFirst);
  final id = uri == null ? null : decisionIdFromDeepLink(uri);
  if (id != null) navigator.pushNamed(decisionRouteName(id));
}

/// Comme [openWidgetLink], une fois le navigateur de [key] construit
/// (lancement à froid : le lien est connu avant la première image).
Future<void> openWidgetLinkWhenReady(
  GlobalKey<NavigatorState> key,
  Uri? uri,
) async {
  for (var frame = 0; frame < 120; frame++) {
    if (key.currentState case final navigator?) {
      openWidgetLink(navigator, uri);
      return;
    }
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
  }
  debugPrint('openWidgetLinkWhenReady : navigateur absent, lien ignoré ($uri)');
}
