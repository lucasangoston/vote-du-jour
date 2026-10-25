import 'package:flutter/material.dart';

import '../decisions_repository.dart';
import 'in_debate_page.dart';

/// Préfixe des routes de l'écran « En débat » : `/en-debat/<dossier>`.
const _prefix = '/en-debat/';

/// Nom de la route de l'écran « En débat » du dossier [dossierRef].
String inDebateRouteName(String dossierRef) =>
    '$_prefix${Uri.encodeComponent(dossierRef)}';

/// Dossier demandé par un lien profond `votedujour://en-debat/<dossier>`
/// (notification d'un texte qui passe en séance, #77), ou `null` pour un
/// autre lien.
String? inDebateRefFromDeepLink(Uri uri) {
  if (uri.scheme != 'votedujour' || uri.host != 'en-debat') return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  return segments.length == 1 ? segments.single : null;
}

/// `onGenerateRoute` de l'app pour `/en-debat/<dossier>` : l'écran du texte
/// en débat, lu dans l'index de [repository].
Route<void>? generateInDebateRoute(
  RouteSettings settings, {
  required DecisionsRepository repository,
}) {
  final name = settings.name;
  if (name == null || !name.startsWith(_prefix)) return null;
  final ref = Uri.decodeComponent(name.substring(_prefix.length));
  if (ref.isEmpty || ref.contains('/')) return null;
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => InDebatePage(dossierRef: ref, repository: repository),
  );
}
