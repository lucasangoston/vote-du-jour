import 'package:flutter/widgets.dart';

import '../decision_detail/decision_route.dart';
import '../in_debate/in_debate_route.dart';

/// Ouvre l'écran demandé par un tap sur un widget : le détail de la décision
/// pour `votedujour://decisions/<id>?homeWidget`, l'accueil sinon
/// (`votedujour://decisions?homeWidget`). Le lien d'une notification de
/// texte en débat (`votedujour://en-debat/<dossier>`, #77) ouvre l'écran
/// « En débat ». L'app revient d'abord à l'accueil, pour qu'un retour depuis
/// l'écran ouvert y mène.
void openWidgetLink(NavigatorState navigator, Uri? uri) {
  navigator.popUntil((route) => route.isFirst);
  if (uri == null) return;
  if (decisionIdFromDeepLink(uri) case final id?) {
    navigator.pushNamed(decisionRouteName(id));
  } else if (inDebateRefFromDeepLink(uri) case final ref?) {
    navigator.pushNamed(inDebateRouteName(ref));
  }
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
