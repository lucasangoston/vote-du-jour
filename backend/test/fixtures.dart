import 'dart:io';

import 'package:archive/archive.dart';

/// Numéros des scrutins enregistrés dans `test/fixtures/scrutins/`.
const fixtureNumeros = [
  217, 289, 504, 519, 1011, 1018, 1194, 2278, 2372, 2633, 2873, 2900, //
  3022, 3054, 4241, 4696, 4758, 4802, 5731, 6346, 7349,
];

File fixtureFile(int numero) =>
    File('test/fixtures/scrutins/VTANR5L17V$numero.json');

/// Scrutins sur l'article unique d'un texte (et votes sur l'ensemble qui les
/// suivent), enregistrés dans `test/fixtures/scrutins/` pour le ticket #22.
const articleUniqueNumeros = [684, 685, 691, 930, 931, 1333, 6902, 7260];

/// Les fixtures réunies dans une archive au format du jeu de données officiel
/// (`json/<uid>.json`) : par défaut [fixtureNumeros].
List<int> fixtureArchive({List<int> numeros = fixtureNumeros}) {
  final archive = Archive();
  for (final n in numeros) {
    archive.addFile(
      ArchiveFile.bytes(
        'json/VTANR5L17V$n.json',
        fixtureFile(n).readAsBytesSync(),
      ),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

/// Les dossiers et documents de `test/fixtures/dossiers/`, réunis dans une
/// archive au format du jeu de données officiel
/// (`json/dossierParlementaire/<uid>.json`, `json/document/<uid>.json`).
List<int> fixtureDossiersArchive({Map<String, String> extra = const {}}) {
  final archive = Archive();
  for (final dir in ['dossierParlementaire', 'document']) {
    final files =
        Directory(
            'test/fixtures/dossiers/$dir',
          ).listSync().whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      archive.addFile(
        ArchiveFile.bytes('json/$dir/$name', f.readAsBytesSync()),
      );
    }
  }
  for (final MapEntry(:key, :value) in extra.entries) {
    archive.addFile(ArchiveFile.string(key, value));
  }
  return ZipEncoder().encodeBytes(archive);
}

/// Les réunions de `test/fixtures/agenda/reunion/`, réunies dans une archive
/// au format de l'agenda officiel (`json/reunion/<uid>.json`). [replace]
/// remplace le contenu d'un fichier (par uid), pour simuler un nouvel agenda.
List<int> fixtureAgendaArchive({Map<String, String> replace = const {}}) {
  final archive = Archive();
  final files =
      Directory(
          'test/fixtures/agenda/reunion',
        ).listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final name = f.uri.pathSegments.last;
    final uid = name.replaceFirst('.json', '');
    archive.addFile(
      replace[uid] != null
          ? ArchiveFile.string('json/reunion/$name', replace[uid]!)
          : ArchiveFile.bytes('json/reunion/$name', f.readAsBytesSync()),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

/// Contenu de la réunion [uid] des fixtures de l'agenda.
String fixtureReunion(String uid) =>
    File('test/fixtures/agenda/reunion/$uid.json').readAsStringSync();
