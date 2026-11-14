import 'package:vote_contract/vote_contract.dart';

/// Lien de chaque post : la page d'accueil de Le Perchoir (l'app n'est pas
/// encore sur les stores).
const postLink = 'leperchoir.app';

/// Longueur maximale d'un post Bluesky, lien compris.
const postMaxLength = 300;

const _months = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin', //
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

/// « 4 novembre 2026 », « 1er octobre 2026 ».
String frenchLongDate(DateTime d) =>
    '${d.day == 1 ? '1er' : d.day} ${_months[d.month - 1]} ${d.year}';

/// Longueur d'un texte telle que la compte Bluesky (en graphèmes) : les
/// points de code la majorent, sans dépasser la limite par erreur.
int postLength(String text) => text.runes.length;

/// Texte du post de [detail] (#110), sans modèle : le verdict et [title]
/// (celui de la carte), les chiffres du bandeau, la position des groupes,
/// l'explication du résumé si tout tient, le lien. Au plus [postMaxLength] :
/// l'explication tombe d'abord, puis la ligne des groupes.
String postText(DecisionDetail detail, {required String title}) {
  final d = detail.decision;
  final censure = d.type == DecisionType.motionDeCensure;
  final head = '${_verdict(d.result)} — ${_sentence(frenchTypography(title))}';
  final figures = _sentence(
    _oneSpace(socialFigures(d.count!, censure: censure)),
  );
  final camps = _campsLine(detail.groups, censure: censure);
  final explanation = switch (d.summary?.explanation) {
    final e? => frenchTypography(e),
    null => null,
  };

  String compose({required bool withCamps, required bool withExplanation}) => [
    head,
    figures,
    if (withCamps && camps != null) camps,
    if (withExplanation && explanation != null) explanation,
    postLink,
  ].join('\n');

  for (final (withCamps, withExplanation) in [
    (true, true),
    (true, false),
    (false, false),
  ]) {
    final text = compose(
      withCamps: withCamps,
      withExplanation: withExplanation,
    );
    if (postLength(text) <= postMaxLength) return text;
  }
  throw StateError('post de ${d.id} trop long, même réduit : « $title »');
}

/// Texte alternatif de l'image de [detail] (#110) : ce que montre la carte,
/// avec les chiffres exacts des données, pour un lecteur d'écran.
String altText(DecisionDetail detail, {required String title}) {
  final d = detail.decision;
  final censure = d.type == DecisionType.motionDeCensure;
  final count = d.count!;
  final stage = d.stage;
  final turnout = socialTurnout(
    count,
    detail.seats?.length ?? 0,
    censure: censure,
  );
  final positions = _positions(detail.groups);
  final hemicycle = censure
      ? 'Hémicycle : en blanc, les députés qui ont voté la motion'
            '${_list(positions[GroupPosition.pour], prefix: ' (', suffix: ')')}'
      : 'Hémicycle coloré par le vote : '
            '${_unanimous(detail.groups) ?? _campParts(positions, spoken: true).join(' ; ')}';
  return [
    'Carte Le Perchoir',
    [?stage, frenchLongDate(d.date)].join(', '),
    frenchTypography(title),
    hemicycle,
    '${_verdict(d.result)}, ${_spokenFigures(count, censure: censure)}',
    ?turnout,
  ].map(_sentence).join(' ').replaceAll(' ', ' ');
}

/// Le bandeau de la carte espace ses chiffres (« 151 pour  ·  187 contre ») ;
/// le texte n'a besoin que d'une espace.
String _oneSpace(String figures) => figures.replaceAll('  ·  ', ' · ');

/// Chiffres en toutes lettres pour un lecteur d'écran : « 151 pour,
/// 187 contre, 2 abstentions » ; motion de censure : « 132 pour, 289
/// requis ».
String _spokenFigures(VoteTally c, {required bool censure}) => [
  '${c.pour} pour',
  if (censure)
    '$censureMajority requis'
  else ...[
    '${c.contre} contre',
    if (c.abstentions > 0)
      c.abstentions == 1 ? '1 abstention' : '${c.abstentions} abstentions',
  ],
].join(', ');

String _verdict(VoteResult r) => r == VoteResult.adopte ? 'Adopté' : 'Rejeté';

/// Termine [s] par un point, sauf s'il finit déjà par une ponctuation forte.
String _sentence(String s) =>
    RegExp(r'[.!?…]$').hasMatch(s.trimRight()) ? s.trimRight() : '$s.';

/// Sigles des groupes par position, dans l'ordre de [groups] (open data :
/// du plus grand au plus petit).
Map<GroupPosition, List<String>> _positions(List<GroupVoteDetail> groups) {
  final byPosition = <GroupPosition, List<String>>{};
  for (final g in groups) {
    byPosition.putIfAbsent(g.position, () => []).add(g.abbreviation ?? g.name);
  }
  return byPosition;
}

/// « Pour : RN, UDR · Contre : EPR, LFI-NFP · Abst. : GDR · NI partagés »,
/// une position vide omise ; « Tous les groupes pour » si tous ont voté de
/// même ; motion de censure : les seuls soutiens. `null` sans groupe.
String? _campsLine(List<GroupVoteDetail> groups, {required bool censure}) {
  final positions = _positions(groups);
  if (censure) {
    final g = positions[GroupPosition.pour];
    return g == null || g.isEmpty
        ? null
        : 'Pour la censure\u00A0: ${g.join(', ')}';
  }
  final unanimous = _unanimous(groups);
  if (unanimous != null) {
    return '${unanimous[0].toUpperCase()}${unanimous.substring(1)}';
  }
  final parts = _campParts(positions, spoken: false);
  return parts.isEmpty ? null : parts.join(' · ');
}

/// « tous les groupes pour » (ou contre, ou abstention) quand plusieurs
/// groupes ont tous pris la même position, sinon `null`.
String? _unanimous(List<GroupVoteDetail> groups) {
  if (groups.length < 2) return null;
  final position = groups.first.position;
  if (groups.any((g) => g.position != position)) return null;
  return switch (position) {
    GroupPosition.pour => 'tous les groupes pour',
    GroupPosition.contre => 'tous les groupes contre',
    GroupPosition.abstention => 'tous les groupes abstentionnistes',
    _ => null,
  };
}

/// Une partie par position : « Pour : RN, UDR » à l'écrit, « pour, RN, UDR »
/// pour un lecteur d'écran ([spoken]) ; les groupes partagés en dernier.
List<String> _campParts(
  Map<GroupPosition, List<String>> positions, {
  required bool spoken,
}) => [
  for (final (p, label) in const [
    (GroupPosition.pour, 'pour'),
    (GroupPosition.contre, 'contre'),
    (GroupPosition.abstention, 'abstention'),
  ])
    if (positions[p] case final g? when g.isNotEmpty)
      spoken
          ? '$label, ${g.join(', ')}'
          : '${p == GroupPosition.abstention ? 'Abst.' : '${label[0].toUpperCase()}${label.substring(1)}'}\u00A0: ${g.join(', ')}',
  if (positions[GroupPosition.partage] case final g? when g.isNotEmpty)
    sharedGroups(g),
];

String _list(List<String>? items, {String prefix = '', String suffix = ''}) =>
    items == null || items.isEmpty ? '' : '$prefix${items.join(', ')}$suffix';
