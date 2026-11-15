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
    this.camps = const [],
    this.unanimous,
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
      title: switch (title ?? d.summary?.shortTitle ?? d.summary?.title) {
        final t? => frenchTypography(t),
        null => null,
      },
      result: d.result,
      figures: socialFigures(count, censure: censure),
      turnout: socialTurnout(count, seats.length, censure: censure),
      censure: censure,
      seats: seats,
      camps: socialCamps(detail.groups),
      unanimous: socialUnanimous(detail.groups),
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

  /// « 102 votants sur 574 », seulement quand moins de la moitié des sièges
  /// a voté.
  final String? turnout;

  /// Motion de censure : seuls les pour comptent, soutiens en encre neutre.
  final bool censure;

  final List<HemicycleSeat> seats;

  /// Groupes par position, pour la légende sous l'hémicycle : la couleur
  /// d'un siège dit le vote, la légende dit qui a voté quoi.
  final List<SocialCamp> camps;

  /// Position commune quand tous les groupes ont voté de même : la légende
  /// tient en « Tous les groupes pour ».
  final GroupPosition? unanimous;

  /// Lignes de la légende : un libellé et, sauf unanimité, ses groupes.
  /// Motion de censure : les seuls soutiens.
  List<({GroupPosition position, String label, String groups})> get legend {
    if (censure) {
      return [
        for (final camp in camps)
          if (camp.position == GroupPosition.pour)
            (
              position: camp.position,
              label: 'Pour la censure',
              groups: camp.groups.join(', '),
            ),
      ];
    }
    if (unanimous case final position?) {
      return [
        (
          position: position,
          label: switch (position) {
            GroupPosition.pour => 'Tous les groupes pour',
            GroupPosition.contre => 'Tous les groupes contre',
            _ => 'Tous les groupes abstentionnistes',
          },
          groups: '',
        ),
      ];
    }
    return [
      for (final camp in camps)
        (
          position: camp.position,
          label: switch (camp.position) {
            GroupPosition.pour => 'Pour',
            GroupPosition.contre => 'Contre',
            GroupPosition.abstention => 'Abst.',
            _ =>
              camp.groups.length == 1 && camp.groups.single != 'NI'
                  ? 'Partagé'
                  : 'Partagés',
          },
          groups: camp.groups.join(', '),
        ),
    ];
  }
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
