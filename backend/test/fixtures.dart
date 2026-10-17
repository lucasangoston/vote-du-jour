import 'dart:io';

import 'package:archive/archive.dart';

/// Numéros des scrutins enregistrés dans `test/fixtures/scrutins/`.
const fixtureNumeros = [
  217, 289, 504, 519, 1018, 1194, 2278, 2372, 2873, 3022, 3054, 4241, //
  4696, 4758, 4802, 5731, 6346, 7349,
];

File fixtureFile(int numero) =>
    File('test/fixtures/scrutins/VTANR5L17V$numero.json');

/// Les fixtures réunies dans une archive au format du jeu de données officiel
/// (`json/<uid>.json`).
List<int> fixtureArchive() {
  final archive = Archive();
  for (final n in fixtureNumeros) {
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
