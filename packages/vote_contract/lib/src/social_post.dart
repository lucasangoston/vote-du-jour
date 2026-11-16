import 'decision.dart';
import 'decision_detail.dart';

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

/// « 102 votants sur 574 » quand moins de la moitié des [seats] sièges du
/// scrutin a voté (pour, contre ou abstention), sinon `null` : la carte
/// paraîtrait vide sans cette mention, et le dénominateur dit qu'un résultat
/// net vient de peu de députés. Jamais pour une motion de censure, où seuls
/// les pour votent.
String? socialTurnout(VoteTally c, int seats, {required bool censure}) {
  if (censure) return null;
  final votants = c.pour + c.contre + c.abstentions;
  if (votants * 2 >= seats) return null;
  return '$votants ${votants == 1 ? 'votant' : 'votants'} sur $seats';
}

/// Un camp de la carte et du texte : les sigles des groupes d'une même
/// position, dans l'ordre de l'open data (du plus grand au plus petit).
typedef SocialCamp = ({GroupPosition position, List<String> groups});

/// Camps de [groups], dans l'ordre pour, contre, abstention, partagés ; une
/// position sans groupe est omise, les groupes qui n'ont pas voté aussi.
List<SocialCamp> socialCamps(List<GroupVoteDetail> groups) => [
  for (final position in const [
    GroupPosition.pour,
    GroupPosition.contre,
    GroupPosition.abstention,
    GroupPosition.partage,
  ])
    if ([
          for (final g in groups)
            if (g.position == position) g.abbreviation ?? g.name,
        ]
        case final sigles when sigles.isNotEmpty)
      (position: position, groups: sigles),
];

/// La position commune quand plusieurs groupes ont tous voté de même (pour,
/// contre ou abstention), sinon `null`.
GroupPosition? socialUnanimous(List<GroupVoteDetail> groups) {
  if (groups.length < 2) return null;
  final position = groups.first.position;
  if (groups.any((g) => g.position != position)) return null;
  return switch (position) {
    GroupPosition.pour ||
    GroupPosition.contre ||
    GroupPosition.abstention => position,
    _ => null,
  };
}

final _spaceBeforeDouble = RegExp(r' +([:;?!»])');
final _spaceAfterGuillemet = RegExp(r'« +');

/// Typographie française d'un texte affiché : espace insécable avant « : »,
/// « ; », « ? », « ! » et « » », et après « « », pour qu'une ligne ne
/// commence jamais par l'un de ces signes.
String frenchTypography(String s) => s
    .replaceAllMapped(_spaceBeforeDouble, (m) => '\u00A0${m[1]}')
    .replaceAll(_spaceAfterGuillemet, '«\u00A0');

/// Groupes partagés, accordés : « SOC partagé », « NI partagés » (les
/// non-inscrits sont plusieurs), « SOC, NI partagés ».
String sharedGroups(List<String> groups) =>
    '${groups.join(', ')} '
    '${groups.length == 1 && groups.single != 'NI' ? 'partagé' : 'partagés'}';

/// Ligne qui sépare deux réponses d'un même fil dans l'issue du jour de la
/// content factory, et dans son aperçu.
const threadSeparator = '---';

final _threadSplit = RegExp(r'^[ \t]*-{3,}[ \t]*$', multiLine: true);

/// Les réponses du fil [reply], dans l'ordre : ses parties séparées par une
/// ligne [threadSeparator], sans les vides. `null` ou vide : aucune.
List<String> threadParts(String? reply) => [
  for (final part in (reply ?? '').split(_threadSplit))
    if (part.trim().isNotEmpty) part.trim(),
];
