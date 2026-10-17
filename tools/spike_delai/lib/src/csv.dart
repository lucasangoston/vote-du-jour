/// CSV minimal (séparateur virgule, guillemets doubles), suffisant pour les
/// relevés du spike.
library;

String ligneCsv(List<Object?> valeurs) => valeurs.map((v) {
      final s = v?.toString() ?? '';
      if (s.contains(RegExp(r'[",\n\r]'))) return '"${s.replaceAll('"', '""')}"';
      return s;
    }).join(',');

List<List<String>> lireCsv(String texte) {
  final lignes = <List<String>>[];
  var champs = <String>[];
  final champ = StringBuffer();
  var entreGuillemets = false;
  for (var i = 0; i < texte.length; i++) {
    final c = texte[i];
    if (entreGuillemets) {
      if (c == '"') {
        if (i + 1 < texte.length && texte[i + 1] == '"') {
          champ.write('"');
          i++;
        } else {
          entreGuillemets = false;
        }
      } else {
        champ.write(c);
      }
    } else if (c == '"') {
      entreGuillemets = true;
    } else if (c == ',') {
      champs.add(champ.toString());
      champ.clear();
    } else if (c == '\n') {
      champs.add(champ.toString());
      champ.clear();
      lignes.add(champs);
      champs = <String>[];
    } else if (c != '\r') {
      champ.write(c);
    }
  }
  if (champ.isNotEmpty || champs.isNotEmpty) {
    champs.add(champ.toString());
    lignes.add(champs);
  }
  return lignes;
}

/// Lit un CSV avec en-tête et renvoie une map par ligne.
List<Map<String, String>> lireCsvAvecEntete(String texte) {
  final lignes = lireCsv(texte);
  if (lignes.isEmpty) return [];
  final entete = lignes.first;
  return [
    for (final l in lignes.skip(1))
      if (l.any((c) => c.isNotEmpty))
        {for (var i = 0; i < entete.length; i++) entete[i]: i < l.length ? l[i] : ''},
  ];
}
