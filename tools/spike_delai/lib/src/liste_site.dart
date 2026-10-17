/// Lecture de la page « liste des scrutins » du site de l'Assemblée
/// (https://www.assemblee-nationale.fr/dyn/17/scrutins).
library;

class ScrutinSite {
  ScrutinSite({required this.numero, required this.titre, required this.seance});

  final int numero;

  /// Titre tel qu'affiché, par exemple « Scrutin public n°8877 sur
  /// l'amendement n° 3865… ».
  final String titre;

  /// Libellé de séance, par exemple « Troisième séance du vendredi 16 octobre
  /// 2026 ». Vide si absent.
  final String seance;
}

final _lienTitre = RegExp(
  r'<a\s+class="link h6"\s+href="/dyn/17/scrutins/(\d+)"[^>]*>([\s\S]*?)</a>',
);
final _seance = RegExp(r'<span class="h6 _colored-primary">([^<]*)</span>');

/// Extrait les scrutins de la page, dans l'ordre d'affichage (du plus récent
/// au plus ancien). Lève une [FormatException] si la page n'en contient aucun :
/// c'est le signe que la structure du site a changé.
List<ScrutinSite> lireListe(String html) {
  final resultat = <ScrutinSite>[];
  final vus = <int>{};
  final liens = _lienTitre.allMatches(html).toList();
  for (var i = 0; i < liens.length; i++) {
    final m = liens[i];
    final numero = int.parse(m.group(1)!);
    if (!vus.add(numero)) continue;
    final fin = i + 1 < liens.length ? liens[i + 1].start : html.length;
    final seance = _seance.firstMatch(html.substring(m.end, fin));
    resultat.add(ScrutinSite(
      numero: numero,
      titre: _texte(m.group(2)!),
      seance: seance == null ? '' : _texte(seance.group(1)!),
    ));
  }
  if (resultat.isEmpty) {
    throw const FormatException('aucun scrutin trouvé dans la liste du site');
  }
  return resultat;
}

String _texte(String html) => html
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&#039;', "'")
    .replaceAll('&quot;', '"')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
