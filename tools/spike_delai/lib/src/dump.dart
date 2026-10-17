/// Lecture minimale de l'archive officielle Scrutins.json.zip.
library;

import 'dart:convert';

import 'package:archive/archive.dart';

class ScrutinDump {
  ScrutinDump({
    required this.numero,
    required this.dateScrutin,
    required this.titre,
    required this.codeTypeVote,
    required this.libelleTypeVote,
    required this.sort,
  });

  final int numero;
  final String dateScrutin;
  final String titre;
  final String codeTypeVote;
  final String libelleTypeVote;
  final String sort;

  static ScrutinDump depuisJson(Map<String, dynamic> json) {
    final s = json['scrutin'] as Map<String, dynamic>;
    final type = (s['typeVote'] as Map<String, dynamic>?) ?? const {};
    final sort = (s['sort'] as Map<String, dynamic>?) ?? const {};
    return ScrutinDump(
      numero: int.parse(s['numero'] as String),
      dateScrutin: (s['dateScrutin'] as String?) ?? '',
      titre: (s['titre'] as String?) ?? '',
      codeTypeVote: (type['codeTypeVote'] as String?) ?? '',
      libelleTypeVote: (type['libelleTypeVote'] as String?) ?? '',
      sort: (sort['code'] as String?) ?? '',
    );
  }
}

final _nomFichier = RegExp(r'V(\d+)\.json$');

Archive _ouvrir(List<int> zip) => ZipDecoder().decodeBytes(zip);

int? _numero(ArchiveFile f) {
  final m = _nomFichier.firstMatch(f.name);
  return m == null ? null : int.parse(m.group(1)!);
}

/// Numéros présents dans l'archive, sans décompresser les fichiers.
Set<int> numerosDuDump(List<int> zip) =>
    _ouvrir(zip).files.where((f) => f.isFile).map(_numero).whereType<int>().toSet();

/// Scrutins de l'archive. Si [seulement] est fourni, ne décompresse que ces
/// numéros-là.
List<ScrutinDump> lireDump(List<int> zip, {Set<int>? seulement}) {
  final resultat = <ScrutinDump>[];
  for (final f in _ouvrir(zip).files) {
    if (!f.isFile) continue;
    final n = _numero(f);
    if (n == null || (seulement != null && !seulement.contains(n))) continue;
    final texte = utf8.decode(f.content as List<int>);
    resultat.add(ScrutinDump.depuisJson(jsonDecode(texte) as Map<String, dynamic>));
  }
  resultat.sort((a, b) => a.numero.compareTo(b.numero));
  return resultat;
}
