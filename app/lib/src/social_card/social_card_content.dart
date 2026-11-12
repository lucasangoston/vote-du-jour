import 'package:vote_contract/vote_contract.dart';

import '../relative_date.dart';

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
      turnout: socialTurnout(count, seats.length, censure: censure),
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

/// Languette de la carte, en capitales, date insécable.
String socialTab(DecisionSummary d) {
  final date = formatShortFrenchDate(d.date).replaceAll(' ', ' ');
  final stage = d.stage;
  return [
    if (stage != null && stage.isNotEmpty) socialStage(stage),
    date,
  ].join(' · ').toUpperCase();
}
