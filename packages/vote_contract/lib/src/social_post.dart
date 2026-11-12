import 'decision.dart';

/// Majorité absolue des membres de l'Assemblée, requise pour adopter une
/// motion de censure.
const censureMajority = 289;

// Formules communes à la carte réseau social (app, #109) et au texte des
// posts (job, #110) de la content factory (#106) : écrites une seule fois
// pour que l'image et le texte disent la même chose.

/// Étape raccourcie pour tenir sur une ligne : « Première partie du budget,
/// 1re lecture à l'AN » devient « 1re partie du budget · 1re lecture ».
String socialStage(String stage) => stage
    .replaceAll('Première partie du budget', '1re partie du budget')
    .replaceAll('Seconde partie du budget', '2e partie du budget')
    .replaceAll(" à l'AN", '')
    .replaceAll(', ', ' · ');

/// « 151 pour · 187 contre », « 0 abst. » omis ; motion de censure (seuls
/// les pour comptent) : « 132 pour · 289 requis ». Chaque nombre reste collé
/// à son mot (espace insécable).
String socialFigures(VoteTally c, {required bool censure}) {
  String part(int n, String word) => '$n $word';
  return [
    part(c.pour, 'pour'),
    if (censure)
      part(censureMajority, 'requis')
    else ...[
      part(c.contre, 'contre'),
      if (c.abstentions > 0) part(c.abstentions, 'abst.'),
    ],
  ].join('  ·  ');
}

/// « 102 votants » quand moins de la moitié des [seats] sièges du scrutin a
/// voté (pour, contre ou abstention), sinon `null` : la carte paraîtrait
/// vide sans cette mention. Pas de dénominateur. Jamais pour une motion de
/// censure, où seuls les pour votent.
String? socialTurnout(VoteTally c, int seats, {required bool censure}) {
  if (censure) return null;
  final votants = c.pour + c.contre + c.abstentions;
  if (votants * 2 >= seats) return null;
  return votants == 1 ? '1 votant' : '$votants votants';
}
