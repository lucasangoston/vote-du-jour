/// Lecture des pages du site de l'Assemblée (liste des scrutins et page d'un
/// scrutin), qui publient un scrutin quelques minutes après le vote, bien
/// avant le jeu de données quotidien.
///
/// Le site n'a pas d'API : on lit le HTML. Toute page dont la structure n'est
/// plus reconnue lève une [FormatException], pour que le job s'arrête
/// proprement au lieu de publier des données fausses.
library;

import 'package:vote_contract/vote_contract.dart';

import '../scrutin.dart';

/// Scrutin lu sur le site, avant sa publication dans le jeu de données.
class SiteScrutin {
  const SiteScrutin({
    required this.numero,
    required this.titre,
    this.result,
    this.pour,
    this.contre,
    this.abstentions,
    this.seance,
    this.date,
  });

  final int numero;

  /// Intitulé sans le préfixe « Scrutin public n°… sur » : même forme que
  /// dans le jeu de données (« l'ensemble du projet de loi… »).
  final String titre;

  /// Sort du scrutin, s'il est affiché.
  final VoteResult? result;

  /// Décompte, s'il est affiché. Une motion de censure n'affiche que les
  /// voix pour.
  final int? pour;
  final int? contre;
  final int? abstentions;

  /// Libellé de la séance (« Troisième séance du vendredi 16 octobre 2026 »).
  final String? seance;

  /// Jour du scrutin, à minuit UTC, tiré du libellé de la séance.
  final DateTime? date;

  /// Identifiant officiel, le même que dans le jeu de données.
  String get uid => 'VTANR5L17V$numero';

  /// Complète les champs absents par ceux de [other] (page du scrutin).
  SiteScrutin completedWith(SiteScrutin other) => SiteScrutin(
    numero: numero,
    titre: titre,
    result: result ?? other.result,
    pour: pour ?? other.pour,
    contre: contre ?? other.contre,
    abstentions: abstentions ?? other.abstentions,
    seance: seance ?? other.seance,
    date: date ?? other.date,
  );

  /// Le scrutin, au format du jeu de données, pour passer par le même
  /// sélecteur. Le site ne donne ni le type de vote, ni le dossier, ni les
  /// non-votants, ni le vote par groupe : le jeu de données du lendemain les
  /// complète. [fallbackDate] sert si la séance n'est pas lisible.
  Scrutin toScrutin({required DateTime fallbackDate}) => Scrutin(
    uid: uid,
    numero: numero,
    date: date ?? fallbackDate,
    titre: titre,
    // Inconnu sur le site : les règles se rabattent sur l'intitulé (motion
    // de censure) ; le garde-fou des scrutins solennels ne s'applique
    // qu'avec le jeu de données.
    codeTypeVote: '',
    libelleTypeVote: '',
    result: result!,
    decompte: Decompte(
      pour: pour ?? 0,
      contre: contre ?? 0,
      abstentions: abstentions ?? 0,
      nonVotants: 0,
    ),
    dossierRef: null,
    groupVotes: const [],
  );

  Map<String, Object?> toJson() => {
    'numero': numero,
    'titre': titre,
    'result': ?result?.json,
    'pour': ?pour,
    'contre': ?contre,
    'abstentions': ?abstentions,
    'seance': ?seance,
    'date': ?(date == null ? null : formatDate(date!)),
  };

  static SiteScrutin fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['numero'] is! int ||
        json['titre'] is! String) {
      throw const FormatException('Scrutin du site : format inattendu');
    }
    int? count(String key) => json[key] is int ? json[key] as int : null;
    return SiteScrutin(
      numero: json['numero'] as int,
      titre: json['titre'] as String,
      result: VoteResult.tryParse(json['result']),
      pour: count('pour'),
      contre: count('contre'),
      abstentions: count('abstentions'),
      seance: json['seance'] is String ? json['seance'] as String : null,
      date: json['date'] is String
          ? DateTime.tryParse('${json['date']}T00:00:00Z')
          : null,
    );
  }

  @override
  String toString() =>
      'SiteScrutin($numero, ${result?.json}, ${date == null ? '?' : formatDate(date!)}, $titre)';
}

/// Scrutins de la page « liste des scrutins »
/// (`https://www.assemblee-nationale.fr/dyn/17/scrutins?limit=50`), du plus
/// récent au plus ancien.
///
/// Lève une [FormatException] si la page ne contient aucun scrutin ou si un
/// bloc de scrutin n'a plus la forme attendue : la structure du site a
/// changé.
List<SiteScrutin> parseScrutinList(String html) {
  final blocks = html.split(_blockStart).skip(1).toList();
  if (blocks.isEmpty) {
    throw const FormatException('liste du site : aucun bloc de scrutin');
  }
  final seen = <int>{};
  return [
    for (final block in blocks)
      if (_parseListBlock(block) case final s when seen.add(s.numero)) s,
  ];
}

/// Page d'un scrutin (`https://www.assemblee-nationale.fr/dyn/17/scrutins/<n>`).
/// Elle reprend l'intitulé, la séance, le décompte et le sort de la liste.
SiteScrutin parseScrutinPage(String html, {required int numero}) {
  final title = _pageTitle.firstMatch(html);
  if (title == null) {
    throw FormatException('page du scrutin $numero : intitulé introuvable');
  }
  final seance = _pageSeance.firstMatch(html);
  return _scrutin(
    numero: numero,
    rawTitle: title.group(1)!,
    rawSeance: seance?.group(1),
    body: html,
  );
}

final _blockStart = RegExp(r'<div class="an-bloc _style-scrutin\b');
final _listLink = RegExp(
  r'<a\s+class="link h6"\s+href="/dyn/17/scrutins/(\d+)"[^>]*>([\s\S]*?)</a>',
);
final _listSeance = RegExp(r'<span class="h6 _colored-primary">([^<]*)</span>');
final _pageTitle = RegExp(r'<p class="h6 _colored">([\s\S]*?)</p>');
final _pageSeance = RegExp(r'<h2 class="h4 _colored">([^<]*)</h2>');

SiteScrutin _parseListBlock(String block) {
  final link = _listLink.firstMatch(block);
  if (link == null) {
    throw const FormatException('liste du site : bloc sans lien de scrutin');
  }
  final seance = _listSeance.firstMatch(block);
  return _scrutin(
    numero: int.parse(link.group(1)!),
    rawTitle: link.group(2)!,
    rawSeance: seance?.group(1),
    body: block,
  );
}

SiteScrutin _scrutin({
  required int numero,
  required String rawTitle,
  required String? rawSeance,
  required String body,
}) {
  final title = htmlText(rawTitle);
  final prefix = _titlePrefix.firstMatch(title);
  if (prefix == null) {
    throw FormatException('scrutin $numero : intitulé inattendu « $title »');
  }
  final counts = {
    for (final m in _count.allMatches(body))
      _countKey(m.group(1)!): int.parse(m.group(2)!),
  };
  final seance = rawSeance == null ? null : htmlText(rawSeance);
  return SiteScrutin(
    numero: numero,
    titre: title.substring(prefix.end),
    result: _result(htmlText(body)),
    pour: counts['pour'],
    contre: counts['contre'],
    abstentions: counts['abstentions'],
    seance: seance == null || seance.isEmpty ? null : seance,
    date: seance == null ? null : seanceDate(seance),
  );
}

/// « Scrutin public n°8877 sur l'amendement… » : le préfixe à retirer pour
/// retrouver l'intitulé du jeu de données.
final _titlePrefix = RegExp(
  r'^Scrutin\b[^°]{0,40}n°\s*\d+\s*(?:sur\s+)?',
  caseSensitive: false,
);

final _count = RegExp(
  r"(Pour l['’]adoption|Contre|Abstentions?)\s*:\s*<b>\s*(\d+)\s*</b>",
);

String _countKey(String label) => switch (label[0]) {
  'P' => 'pour',
  'C' => 'contre',
  _ => 'abstentions',
};

final _resultText = RegExp(
  r"L['’]Assemblée nationale (n['’]a pas adopté|a adopté)",
);

VoteResult? _result(String text) =>
    switch (_resultText.firstMatch(text)?.group(1)) {
      null => null,
      final r when r.startsWith('n') => VoteResult.rejete,
      _ => VoteResult.adopte,
    };

const _months = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin', //
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

final _date = RegExp(
  '(\\d{1,2})(?:er)?\\s+(${_months.join('|')})\\s+(\\d{4})',
  caseSensitive: false,
);

/// Jour d'un libellé de séance (« Première séance du jeudi 1er octobre
/// 2026 »), à minuit UTC, ou `null`.
DateTime? seanceDate(String seance) {
  final m = _date.firstMatch(seance);
  if (m == null) return null;
  return DateTime.utc(
    int.parse(m.group(3)!),
    _months.indexOf(m.group(2)!.toLowerCase()) + 1,
    int.parse(m.group(1)!),
  );
}

/// Texte d'un fragment HTML : balises retirées, entités décodées, apostrophes
/// typographiques et espaces normalisés.
String htmlText(String html) => html
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAllMapped(
      RegExp(r'&#(x[0-9a-fA-F]+|\d+);'),
      (m) => String.fromCharCode(
        m.group(1)!.startsWith('x')
            ? int.parse(m.group(1)!.substring(1), radix: 16)
            : int.parse(m.group(1)!),
      ),
    )
    .replaceAll('&quot;', '"')
    .replaceAll('&rsquo;', '’')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'[\s  ]+'), ' ')
    .trim();
