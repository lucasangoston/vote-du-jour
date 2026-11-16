import 'package:vote_contract/vote_contract.dart';

import 'content_selection.dart';

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

/// Mot-dièse de tous les posts, puis celui du type de décision : les fils
/// thématiques de Bluesky se nourrissent de mots-dièse.
const postTag = '#AssembléeNationale';

/// Texte du post de [detail] (#110), sans modèle : le verdict, ce qui le
/// rend remarquable ([_qualifier]) et [title] (celui de la carte), les
/// chiffres du bandeau, un fait saillant ([postFact]), l'explication du
/// résumé, les mots-dièse, le lien. Les groupes sont sur la carte et dans
/// son texte alternatif, pas ici. Au plus [postMaxLength] : les mots-dièse
/// tombent d'abord, puis l'explication, puis le fait saillant.
String postText(DecisionDetail detail, {required String title}) {
  final d = detail.decision;
  final censure = d.type == DecisionType.motionDeCensure;
  final head =
      '${_verdict(d.result)}${_qualifier(d)} — '
      '${_sentence(frenchTypography(title))}';
  final figures = _sentence(
    _oneSpace(socialFigures(d.count!, censure: censure)),
  );
  final fact = postFact(detail);
  final explanation = switch (d.summary?.explanation) {
    final e? => frenchTypography(e),
    null => null,
  };
  final tags = postTags(d).join(' ');

  String compose({
    required bool withFact,
    required bool withExplanation,
    required bool withTags,
  }) => [
    head,
    figures,
    if (withFact && fact != null) fact,
    if (withExplanation && explanation != null) explanation,
    if (withTags) tags,
    postLink,
  ].join('\n');

  for (final (withFact, withExplanation, withTags) in [
    (true, true, true),
    (true, true, false),
    (true, false, true),
    (true, false, false),
    (false, false, false),
  ]) {
    final text = compose(
      withFact: withFact,
      withExplanation: withExplanation,
      withTags: withTags,
    );
    if (postLength(text) <= postMaxLength) return text;
  }
  throw StateError('post de ${d.id} trop long, même réduit : « $title »');
}

/// Ce qui rend le verdict remarquable, à la suite de « Adopté » ou
/// « Rejeté » : « à l'unanimité », « sans voix contre », « sans voix pour »,
/// « à 3 voix près » ([isTightVote]), « à égalité des voix ». Vide sinon, et
/// pour une motion de censure (seuls les pour y comptent).
String _qualifier(DecisionSummary d) {
  final c = d.count;
  if (c == null || d.type == DecisionType.motionDeCensure) return '';
  if (c.pour + c.contre == 0) return '';
  if (d.result == VoteResult.adopte && c.contre == 0) {
    return c.abstentions == 0 ? ' à l\'unanimité' : ' sans voix contre';
  }
  if (d.result == VoteResult.rejete && c.pour == 0) return ' sans voix pour';
  if (!isTightVote(d)) return '';
  final margin = (c.pour - c.contre).abs();
  return margin == 0 ? ' à égalité des voix' : ' à $margin voix près';
}

/// Le fait saillant du scrutin de [detail], en une phrase factuelle, ou
/// `null` : la raison de s'arrêter sur ce vote, que les chiffres seuls ne
/// disent pas. Dans l'ordre : les voix qui ont manqué à une motion de
/// censure, des abstentions plus nombreuses que chaque camp, une faible
/// participation ([socialTurnout]), un groupe partagé.
String? postFact(DecisionDetail detail) {
  final d = detail.decision;
  final c = d.count;
  if (c == null) return null;
  if (d.type == DecisionType.motionDeCensure) {
    final missing = censureMajority - c.pour;
    return missing > 0 && d.result == VoteResult.rejete
        ? 'Il manquait $missing voix sur les $censureMajority requises.'
        : null;
  }
  if (c.abstentions > c.pour && c.abstentions > c.contre) {
    return 'Plus d\'abstentions (${c.abstentions}) que de votes pour ou '
        'contre.';
  }
  final seats = detail.seats?.length ?? 0;
  if (socialTurnout(c, seats, censure: false) != null) {
    final votants = c.pour + c.contre + c.abstentions;
    return votants == 1
        ? '1 député sur $seats a voté.'
        : '$votants députés sur $seats ont voté.';
  }
  final shared = [
    for (final camp in socialCamps(detail.groups))
      if (camp.position == GroupPosition.partage)
        ...camp.groups.where((g) => g != 'NI'),
  ];
  if (shared.isEmpty) return null;
  return '${shared.length == 1 ? 'Groupe partagé' : 'Groupes partagés'}'
      ' : ${shared.join(', ')}.';
}

/// Mots-dièse du post de [d] : [postTag], puis celui du type de décision.
List<String> postTags(DecisionSummary d) => [
  postTag,
  ...switch (d.type) {
    DecisionType.motionDeCensure => const ['#MotionDeCensure'],
    DecisionType.premierePartieBudget => const ['#Budget'],
    _ => const <String>[],
  },
];

/// Lien affiché vers la page officielle [sourceUrl] du scrutin, sans
/// `https://www.` : le post compte chaque caractère, et la facette
/// ([richTextFacets]) rend le lien cliquable.
String sourceLink(String sourceUrl) =>
    sourceUrl.replaceFirst(RegExp(r'^https?://(www\.)?'), '');

/// Fil publié sous le post de [detail] (#112) : ce qui se discute sous un
/// vote. Une réponse par camp avec son premier argument avancé en séance,
/// attribué à son groupe, quand deux camps au moins se sont exprimés ; sinon
/// les points du résumé qui tiennent dans une réponse. Le lien du scrutin
/// officiel ferme le fil. Réponses séparées par [threadSeparator], chacune
/// d'au plus [postMaxLength].
String replyText(DecisionDetail detail) {
  final d = detail.decision;
  final source = 'Scrutin officiel : ${sourceLink(d.sourceUrl)}';
  bool fits(String text) => postLength(text) <= postMaxLength;

  String argument(String camp, GroupArgument a) =>
      '$camp (${a.group}) : ${_sentence(frenchTypography(a.text))}';

  final a = detail.arguments;
  // Un seul camp ne dit pas le débat : deux au moins, ou les points.
  final arguments = [
    if (a?.pour.firstOrNull case final x?) argument('Pour', x),
    if (a?.contre.firstOrNull case final x?) argument('Contre', x),
    if (a?.abstention.firstOrNull case final x?) argument('Abstention', x),
  ].take(2).toList();
  final parts = <String>[];
  if (arguments.length == 2 && arguments.every(fits)) {
    const title = 'Les arguments en séance.';
    final first = '$title\n${arguments.first}';
    parts
      ..add(fits(first) ? first : arguments.first)
      ..add(arguments.last);
  } else {
    final points = [
      for (final p in d.summary?.points ?? const <String>[])
        '• ${_sentence(frenchTypography(p))}',
    ];
    for (var n = points.length; n > 0; n--) {
      final text = ['Ce que prévoit le texte :', ...points.take(n)].join('\n');
      if (fits(text)) {
        parts.add(text);
        break;
      }
    }
  }
  if (parts.isNotEmpty && fits('${parts.last}\n$source')) {
    parts.last = '${parts.last}\n$source';
  } else {
    parts.add(source);
  }
  return parts.join('\n$threadSeparator\n');
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
  final camps = socialCamps(detail.groups);
  final supporters = [
    for (final camp in camps)
      if (camp.position == GroupPosition.pour) ...camp.groups,
  ];
  final hemicycle = censure
      ? 'Hémicycle : en blanc, les députés qui ont voté la motion'
            '${supporters.isEmpty ? '' : ' (${supporters.join(', ')})'}'
      : 'Hémicycle coloré par le vote : '
            '${_unanimous(detail.groups) ?? camps.map(_spokenCamp).join(' ; ')}';
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

/// « tous les groupes pour » (ou contre, ou abstentionnistes) quand
/// plusieurs groupes ont tous pris la même position, sinon `null`.
String? _unanimous(List<GroupVoteDetail> groups) =>
    switch (socialUnanimous(groups)) {
      GroupPosition.pour => 'tous les groupes pour',
      GroupPosition.contre => 'tous les groupes contre',
      GroupPosition.abstention => 'tous les groupes abstentionnistes',
      _ => null,
    };

/// Un camp pour un lecteur d'écran : « pour, RN, UDR », « NI partagés ».
String _spokenCamp(SocialCamp camp) => switch (camp.position) {
  GroupPosition.partage => sharedGroups(camp.groups),
  final p => '${p.json}, ${camp.groups.join(', ')}',
};
