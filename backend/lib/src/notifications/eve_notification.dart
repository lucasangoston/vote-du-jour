import 'package:vote_contract/vote_contract.dart';

import '../live/paris_time.dart';
import 'fcm_client.dart';

/// Les notifications de la veille d'un vote solennel (#54) partent lors
/// d'un passage dont l'heure de Paris est comprise entre [eveStartHour] h
/// et minuit.
///
/// Limite : le passage horaire de `publish.yml` dépend du cron de GitHub,
/// irrégulier (#51). Sans aucun passage entre 18h et 23h59, la notification
/// de la veille n'est pas envoyée (elle ne part jamais le jour même).
const eveStartHour = 18;

/// Lien profond vers la liste des décisions, où l'app affiche les points à
/// venir (même lien que celui d'un widget sans décision).
const listDeepLink = 'votedujour://decisions';

/// Clé du point [item] dans la mémoire des notifications : séance et
/// dossier, pour qu'un point republié sous un autre identifiant dans la
/// même séance ne soit pas annoncé deux fois (identifiant du point à
/// défaut de dossier).
String eveNotificationKey(UpcomingItem item) =>
    '${item.seanceRef} ${item.dossierRef ?? item.id}';

/// À l'instant [now], le point [item] doit-il être annoncé comme vote
/// solennel du lendemain ?
///
/// - vote solennel (le bloc « À venir » ne contient que des points
///   « Confirmé » de l'agenda : un point supprimé ou reporté n'y est plus,
///   ou plus à cette date) ;
/// - passage du soir (de [eveStartHour] h à 23h59, heure de Paris) ;
/// - séance le lendemain, heure de Paris.
bool isEveNotificationDue(UpcomingItem item, DateTime now) {
  if (item.kind != UpcomingKind.voteSolennel) return false;
  final paris = toParis(now);
  if (paris.hour < eveStartHour) return false;
  final tomorrow = DateTime.utc(paris.year, paris.month, paris.day + 1);
  return parisDay(item.startsAt) == tomorrow;
}

/// Notification de la veille : « Vote solennel demain », « À partir de
/// 15h : titre court » (heure de Paris du début de la séance), lien vers la
/// liste. Pas de `decisionId` : l'app s'ouvre sur la liste.
PushMessage eveNotificationFor(UpcomingItem item, {required String topic}) {
  final start = toParis(item.startsAt);
  final hour = start.minute == 0
      ? '${start.hour}h'
      : '${start.hour}h${start.minute.toString().padLeft(2, '0')}';
  final title = item.shortTitle.trim().replaceAll(RegExp(r'\s+'), ' ');
  return PushMessage(
    topic: topic,
    title: 'Vote solennel demain',
    body:
        'À partir de $hour : '
        '${title.length <= 150 ? title : '${title.substring(0, 149).trimRight()}…'}',
    data: {'upcomingId': item.id, 'link': listDeepLink},
  );
}
