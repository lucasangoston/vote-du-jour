/// Nature du texte source d'un résumé, par ordre de préférence.
enum SourceKind {
  /// Exposé des motifs du texte déposé (propositions et projets déposés à
  /// l'Assemblée).
  expose('expose'),

  /// Articles du texte, quand il n'a pas d'exposé des motifs (texte transmis
  /// par le Sénat).
  articles('articles'),

  /// Intitulé seul : pas de texte (motion de censure, déclaration du
  /// Gouvernement), ou texte introuvable.
  titre('titre');

  const SourceKind(this.json);

  final String json;

  static SourceKind? tryParse(Object? value) =>
      SourceKind.values.where((k) => k.json == value).firstOrNull;
}

/// Extrait du texte officiel donné au modèle.
class SourceText {
  const SourceText({
    required this.kind,
    required this.text,
    this.truncated = false,
  });

  final SourceKind kind;
  final String text;

  /// Le texte a été coupé à [maxSourceChars] caractères.
  final bool truncated;
}

/// Longueur maximale du texte source, en caractères (environ 6 000 jetons) :
/// l'essentiel d'un exposé des motifs, en bornant le coût d'un appel. Un
/// texte plus long est coupé à la fin d'un paragraphe.
const maxSourceChars = 24000;

/// Un exposé plus court est jugé vide (page mal découpée) : on passe aux
/// articles.
const _minExposeChars = 200;
const _minArticlesChars = 40;

/// Tire de la page HTML d'un texte de l'Assemblée
/// (`https://www.assemblee-nationale.fr/dyn/opendata/<uid>.html`) son exposé
/// des motifs, sinon ses articles ; `null` si la page ne contient ni l'un ni
/// l'autre.
///
/// La page est une donnée non fiable : elle n'est jamais interprétée, seul
/// son texte est extrait (balises, styles et scripts retirés).
SourceText? extractSourceText(String html, {int maxChars = maxSourceChars}) {
  final lines = htmlToLines(html);
  final exposeAt = lines.indexWhere(
    (l) => _exposeHeading.hasMatch(l.toLowerCase()),
  );
  if (exposeAt >= 0) {
    final end = _dispositifStart(lines, exposeAt + 1);
    final expose = [
      for (final l in lines.sublist(exposeAt + 1, end))
        if (!_salutation.hasMatch(l)) l,
    ];
    final text = expose.join('\n');
    if (text.length >= _minExposeChars) {
      return _truncated(SourceKind.expose, text, maxChars);
    }
  }
  final articlesAt = lines.indexWhere(_isArticleHeading);
  if (articlesAt < 0) return null;
  final articles = <String>[];
  for (final l in lines.skip(articlesAt)) {
    if (_endOfText.hasMatch(l)) break;
    articles.add(l);
  }
  final text = articles.join('\n');
  if (text.length < _minArticlesChars) return null;
  return _truncated(SourceKind.articles, text, maxChars);
}

/// Texte d'une page HTML, une ligne par paragraphe, sans lignes vides ni
/// numéros de page (« – 1 – »).
List<String> htmlToLines(String html) {
  var s = html.replaceAll(
    RegExp(
      r'<(head|style|script)\b.*?</\1\s*>',
      caseSensitive: false,
      dotAll: true,
    ),
    ' ',
  );
  s = s.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ');
  s = s.replaceAll(
    RegExp(
      r'</(p|div|h[1-6]|li|tr|td|table|section)\s*>|<br\s*/?>',
      caseSensitive: false,
    ),
    '\n',
  );
  s = s.replaceAll(RegExp(r'<[^>]*>'), '');
  s = decodeHtmlEntities(s);
  return [
    for (final raw in s.split('\n'))
      if (raw.replaceAll(RegExp(r'\s+'), ' ').trim() case final l
          when l.isNotEmpty && !_pageNumber.hasMatch(l))
        l,
  ];
}

/// Décode les entités HTML numériques (`&#xa0;`, `&#8217;`) et les entités
/// nommées courantes. Les espaces insécables deviennent des espaces, le
/// trait d'union insécable un trait d'union.
String decodeHtmlEntities(String s) => s
    .replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);'), (m) {
      final e = m.group(1)!;
      int? code;
      if (e.startsWith('#x') || e.startsWith('#X')) {
        code = int.tryParse(e.substring(2), radix: 16);
      } else if (e.startsWith('#')) {
        code = int.tryParse(e.substring(1));
      } else {
        return _namedEntities[e] ?? m.group(0)!;
      }
      if (code == null || code <= 0 || code > 0x10FFFF) return m.group(0)!;
      return String.fromCharCode(code);
    })
    .replaceAll(RegExp('[   ]'), ' ')
    .replaceAll('‑', '-');

const _namedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'laquo': '«',
  'raquo': '»',
  'rsquo': '’',
  'lsquo': '‘',
  'ldquo': '“',
  'rdquo': '”',
  'hellip': '…',
  'ndash': '–',
  'mdash': '—',
  'eacute': 'é',
  'egrave': 'è',
  'agrave': 'à',
  'ccedil': 'ç',
  'deg': '°',
};

final _exposeHeading = RegExp(r'^expos[ée] des motifs\.?$');
final _salutation = RegExp(r'^mesdames,? messieurs,?$', caseSensitive: false);
final _pageNumber = RegExp(r'^[–-]\s*\d+\s*[–-]$');

/// Titre du dispositif qui suit l'exposé (« PROPOSITION DE LOI », « PROJET
/// DE LOI ORGANIQUE »…).
final _dispositifTitle = RegExp(
  r'^(proposition de (loi|résolution)|projet de loi)'
  r'( (organique|constitutionnelle|européenne))?$',
  caseSensitive: false,
);

/// Intitulé d'article (« Article 1er », « Article unique », « Article 3 bis
/// (nouveau) »), sur une ligne à part.
final _articleHeading = RegExp(
  r'^article (1er|premier|unique|liminaire|\d+)\b',
  caseSensitive: false,
);

bool _isArticleHeading(String l) =>
    l.length <= 60 && _articleHeading.hasMatch(l);

/// Fin des articles : signature du Sénat, notes de bas de page.
final _endOfText = RegExp(
  r'^(Délibéré en séance publique|\[\(\d+\)\]|\(\d+\) Ce groupe est composé)',
);

/// Début du dispositif après l'exposé : son titre, sinon le premier
/// intitulé d'article, sinon la fin de la page.
int _dispositifStart(List<String> lines, int from) {
  for (var i = from; i < lines.length; i++) {
    if (_dispositifTitle.hasMatch(lines[i])) return i;
  }
  for (var i = from; i < lines.length; i++) {
    if (_isArticleHeading(lines[i])) return i;
  }
  return lines.length;
}

SourceText _truncated(SourceKind kind, String text, int maxChars) {
  if (text.length <= maxChars) return SourceText(kind: kind, text: text);
  final cut = text.lastIndexOf('\n', maxChars);
  final kept = text.substring(0, cut > maxChars ~/ 2 ? cut : maxChars);
  return SourceText(kind: kind, text: kept, truncated: true);
}
