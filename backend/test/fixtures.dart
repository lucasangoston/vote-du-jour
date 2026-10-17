import 'dart:io';

import 'package:archive/archive.dart';

/// Numéros des scrutins enregistrés dans `test/fixtures/scrutins/`.
const fixtureNumeros = [
  217, 519, 1018, 2278, 2372, 2873, 3022, 3054, 4241, 4802, 5731, 7349, //
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
