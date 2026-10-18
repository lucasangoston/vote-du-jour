import 'package:flutter/material.dart';
import 'package:vote_contract/vote_contract.dart';

import 'decision_detail_page.dart';
import 'decision_detail_repository.dart';

/// Préfixe des routes de détail : `/decisions/<id>`.
const _prefix = '/decisions/';

/// Nom de la route du détail de la décision [id].
String decisionRouteName(String id) => '$_prefix${Uri.encodeComponent(id)}';

/// Vrai pour une route de détail de décision.
bool isDecisionRoute(String? name) =>
    name != null && name.startsWith(_prefix) && name.length > _prefix.length;

/// Identifiant de la décision demandée par un lien profond
/// `votedujour://decisions/<id>` (lien des widgets), ou `null` pour un lien
/// vers la liste (`votedujour://decisions`) ou un autre lien.
String? decisionIdFromDeepLink(Uri uri) {
  if (uri.scheme != 'votedujour' || uri.host != 'decisions') return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  return segments.length == 1 ? segments.single : null;
}

/// `onGenerateRoute` de l'app : construit l'écran de détail pour
/// `/decisions/<id>`. L'argument facultatif est la [DecisionSummary] déjà
/// connue (tap dans la liste), affichée pendant le chargement du détail.
Route<void>? generateDecisionRoute(
  RouteSettings settings, {
  DecisionDetailRepository? repository,
}) {
  final name = settings.name;
  if (name == null || !name.startsWith(_prefix)) return null;
  final id = Uri.decodeComponent(name.substring(_prefix.length));
  if (id.isEmpty || id.contains('/')) return null;
  final summary = settings.arguments;
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => DecisionDetailPage(
      id: id,
      repository: repository ?? defaultDecisionDetailRepository,
      summary: summary is DecisionSummary ? summary : null,
    ),
  );
}

/// Ouvre le détail de [decision] au tap sur [child] (ligne de la liste). La
/// ligne s'affiche dans le détail pendant son chargement.
class OpenDecisionOnTap extends StatelessWidget {
  const OpenDecisionOnTap({
    super.key,
    required this.decision,
    required this.child,
  });

  final DecisionSummary decision;
  final Widget child;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => Navigator.of(
      context,
    ).pushNamed(decisionRouteName(decision.id), arguments: decision),
    child: child,
  );
}
