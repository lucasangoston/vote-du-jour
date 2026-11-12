import 'package:vote_contract/vote_contract.dart';

import '../relative_date.dart';

/// Majorité absolue des membres de l'Assemblée, requise pour adopter une
/// motion de censure.
const censureMajority = 289;

/// Ce que dit la carte réseau social d'une décision (#109), sans mise en
/// page : la content factory (#106) la rend en PNG avec [SocialCard].
///
/// Une carte n'existe que pour un scrutin public avec décompte et sièges
/// ([SocialCardContent.of] rend `null` sinon).
class SocialCardContent {
  const SocialCardContent({
    required this.tab,
    required this.title,
    required this.result,
    required this.figures,
    required this.turnout,
    required this.censure,
    required this.seats,
  });

  /// Construit la carte de [detail]. [title] remplace le titre du résumé
  /// (titre écrit à la main dans l'issue du jour).
  static SocialCardContent? of(DecisionDetail detail, {String? title}) {
    final d = detail.decision;
    final count = d.count;
    final seats = detail.seats;
    if (d.voteMode != VoteMode.scrutinPublic ||
        count == null ||
        seats == null ||
        seats.isEmpty) {
      return null;
    }
    final censure = d.type == DecisionType.motionDeCensure;
    return SocialCardContent(
      tab: socialTab(d),
      title: title ?? d.summary?.shortTitle ?? d.summary?.title,
      result: d.result,
      figures: socialFigures(count, censure: censure),
      turnout: censure ? null : socialTurnout(count, seats.length),
      censure: censure,
      seats: seats,
    );
  }

  /// Languette : « 1RE PARTIE DU BUDGET · 1RE LECTURE · 4 NOV. 2026 ».
  final String tab;

  /// Titre : celui écrit à la main, sinon le titre court du résumé, sinon
  /// son titre. `null` sans résumé : titre à écrire.
  final String? title;

  final VoteResult result;

  /// Chiffres du bandeau, sur une ligne.
  final String figures;

  /// « 102 votants », seulement quand moins de la moitié des sièges a voté.
  final String? turnout;

  /// Motion de censure : seuls les pour comptent, soutiens en encre neutre.
  final bool censure;

  final List<HemicycleSeat> seats;
}

/// Étape raccourcie pour tenir sur une ligne : « Première partie du budget,
/// 1re lecture à l'AN » devient « 1re partie du budget · 1re lecture ».
String shortStage(String stage) => stage
    .replaceAll('Première partie du budget', '1re partie du budget')
    .replaceAll('Seconde partie du budget', '2e partie du budget')
    .replaceAll(" à l'AN", '')
    .replaceAll(', ', ' · ');

/// Languette de la carte, en capitales, date insécable.
String socialTab(DecisionSummary d) {
  final date = formatShortFrenchDate(d.date).replaceAll(' ', ' ');
  final stage = d.stage;
  return [
    if (stage != null && stage.isNotEmpty) shortStage(stage),
    date,
  ].join(' · ').toUpperCase();
}

/// « 151 pour · 187 contre », « 0 abst. » omis ; motion de censure :
/// « 132 pour · 289 requis ». Chaque nombre reste collé à son mot.
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
/// vide sans cette mention. Pas de dénominateur.
String? socialTurnout(VoteTally c, int seats) {
  final votants = c.pour + c.contre + c.abstentions;
  if (votants * 2 >= seats) return null;
  return votants == 1 ? '1 votant' : '$votants votants';
}
