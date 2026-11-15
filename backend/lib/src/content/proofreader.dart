import 'package:vote_contract/vote_contract.dart';

import 'post_text.dart';

/// Mots évaluatifs interdits (#120) : ceux de la consigne des résumés
/// (`summary_prompt.dart`, « Neutralité »), avec leurs accords, et quelques
/// jugements courants. Le post décrit, il ne juge pas.
final _evaluative = RegExp(
  r'(?<![\p{L}])('
  r'importante?s?|historiques?|injustes?|justes?|nécessaires?|'
  r'ambitieu(?:x|se|ses)|controversée?s?|enfin|malheureusement|'
  r'scandaleu(?:x|se|ses)|honteu(?:x|se|ses)|inacceptables?|'
  r'incroyables?|désastreu(?:x|se|ses)|formidables?|excellente?s?|'
  r'heureusement|courageu(?:x|se|ses)|absurdes?'
  r')(?![\p{L}])',
  caseSensitive: false,
  unicode: true,
);

final _spaceBeforeDouble = RegExp(r' [:;?!»]');
final _lineStartsWithPunctuation = RegExp(r'^[:;?!.,»)]', multiLine: true);
final _spaceBeforeSimple = RegExp(r'[  ][,.](?!\w)');
final _doubleSpace = RegExp(r'[  ]{2,}');
final _figure = RegExp(r'(\d+)[  ](pour|contre|abst\.|abstentions?|requis)');
final _groupLine = RegExp(
  r'(?:Pour la censure|Pour|Contre|Abst\.) ?: ([^·\n]+)',
);
final _sharedGroups = RegExp(r'(?:^|· )([^·\n:]+) partagés?$', multiLine: true);

/// Problèmes du brouillon de [detail] : [text] (post) et [alt] (texte
/// alternatif), tels que générés ou édités. Liste vide : relecture OK.
/// Règles (#120) : typographie, longueur, chiffres, neutralité, groupes,
/// complétude.
List<String> proofread(
  DecisionDetail detail, {
  required String text,
  required String? alt,
}) {
  final d = detail.decision;
  final problems = <String>[];

  // Typographie (le texte alternatif n'est pas affiché : seulement le post).
  if (_spaceBeforeDouble.hasMatch(text)) {
    problems.add('espace ordinaire avant « : ; ? ! » (insécable attendue)');
  }
  if (_lineStartsWithPunctuation.hasMatch(text)) {
    problems.add('une ligne commence par une ponctuation');
  }
  if (_spaceBeforeSimple.hasMatch(text)) {
    problems.add('espace avant « , » ou « . »');
  }
  if (_doubleSpace.hasMatch(text)) problems.add('double espace');

  // Longueur.
  final length = postLength(text);
  if (length > postMaxLength) {
    problems.add('$length caractères, $postMaxLength au plus');
  }

  // Complétude.
  // Le verdict ouvre le post, suivi au plus d'une précision (« à
  // l'unanimité », « à 3 voix près ») avant le tiret.
  final verdict = d.result == VoteResult.adopte ? 'Adopté' : 'Rejeté';
  if (!RegExp('^$verdict( [^—\n]{1,40})? — ').hasMatch(text)) {
    problems.add('le post ne commence pas par « $verdict — »');
  }
  if (!text.trimRight().endsWith(postLink)) {
    problems.add('le lien $postLink manque en fin de post');
  }
  if (alt == null || alt.trim().isEmpty) {
    problems.add('texte alternatif absent');
  }

  // Chiffres : ceux des données, ni plus ni moins.
  final count = d.count;
  if (count != null) {
    final censure = d.type == DecisionType.motionDeCensure;
    problems
      ..addAll(_checkFigures('post', text, count, censure: censure))
      ..addAll(
        alt == null
            ? const []
            : _checkFigures('texte alternatif', alt, count, censure: censure),
      );
  }

  // Neutralité.
  for (final (where, s) in [('post', text), ('texte alternatif', alt ?? '')]) {
    for (final m in _evaluative.allMatches(s)) {
      problems.add('mot évaluatif « ${m[1]} » dans le $where');
    }
  }

  // Groupes : seulement les sigles du scrutin.
  final known = {
    for (final g in detail.groups) ...[g.abbreviation ?? g.name, g.name],
  };
  final cited = [
    for (final m in _groupLine.allMatches(text)) ...m[1]!.split(', '),
    for (final m in _sharedGroups.allMatches(text)) ...m[1]!.split(', '),
  ].map((g) => g.trim()).where((g) => g.isNotEmpty);
  for (final g in cited) {
    if (!known.contains(g)) problems.add('groupe inconnu « $g »');
  }

  return problems;
}

/// Chiffres de [s] comparés au décompte [c] : chaque chiffre attendu est
/// présent et aucun n'est faux.
List<String> _checkFigures(
  String where,
  String s,
  VoteTally c, {
  required bool censure,
}) {
  final expected = <String, int>{
    'pour': c.pour,
    if (censure) 'requis': censureMajority else 'contre': c.contre,
    if (!censure && c.abstentions > 0) 'abst': c.abstentions,
  };
  final found = <String, int>{};
  final problems = <String>[];
  for (final m in _figure.allMatches(s)) {
    final word = m[2]!.startsWith('abst') ? 'abst' : m[2]!;
    final n = int.parse(m[1]!);
    found[word] = n;
    final want = expected[word];
    if (want == null) {
      if (!(word == 'abst' && n == 0)) {
        problems.add('chiffre « ${m[0]} » inattendu dans le $where');
      }
    } else if (want != n) {
      problems.add('$where : $n $word au lieu de $want');
    }
  }
  for (final MapEntry(key: word, value: n) in expected.entries) {
    if (!found.containsKey(word)) {
      problems.add('$where : « $n $word » manque');
    }
  }
  return problems;
}

/// Problèmes du fil [reply] (#112), tel que généré ou édité : la longueur
/// de chaque réponse ([threadParts]) seulement. Les arguments y sont
/// attribués à leur groupe, avec ses mots : la règle de neutralité du post
/// ne s'y applique pas.
List<String> proofreadReply(String? reply) => [
  for (final (i, part) in threadParts(reply).indexed)
    if (postLength(part) > postMaxLength)
      'réponse ${i + 1} du fil : ${postLength(part)} caractères, '
          '$postMaxLength au plus',
];
