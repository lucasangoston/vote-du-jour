import 'package:vote_contract/vote_contract.dart';

import '../live/paris_time.dart';
import 'fcm_client.dart';

/// Lien profond vers l'écran « En débat » du texte du dossier [dossierRef]
/// (`inDebateRefFromDeepLink` de l'app).
String inDebateDeepLink(String dossierRef) =>
    'votedujour://en-debat/${Uri.encodeComponent(dossierRef)}';

/// À l'instant [now], le texte en débat [inDebate] doit-il être annoncé
/// (#77) ? Oui le jour de la séance (heure de Paris), une fois celle-ci
/// commencée : un texte repéré après coup (job longtemps arrêté) n'est plus
/// « en débat aujourd'hui ».
bool isDebateNotificationDue(InDebate inDebate, DateTime now) =>
    !inDebate.startsAt.isAfter(now) &&
    parisDay(inDebate.startsAt) == parisDay(now);

/// Notification d'un texte qui passe en séance : « En débat aujourd'hui »,
/// « Titre court : les députés examinent le texte. » (titre court du
/// résumé, sinon celui du bloc), lien vers l'écran du texte.
PushMessage debateNotificationFor(InDebate inDebate, {required String topic}) {
  final title = (inDebate.summary?.shortTitle ?? inDebate.shortTitle)
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  return PushMessage(
    topic: topic,
    title: 'En débat aujourd’hui',
    body:
        '${title.length <= 120 ? title : '${title.substring(0, 119).trimRight()}…'}'
        ' : les députés examinent le texte.',
    data: {
      'dossierRef': inDebate.dossierRef,
      'link': inDebateDeepLink(inDebate.dossierRef),
    },
  );
}
