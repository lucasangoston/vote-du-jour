import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Copie locale du dernier index téléchargé, pour afficher la liste hors
/// ligne. Le contenu est le JSON publié tel quel (`v1/latest.json`).
abstract interface class DecisionsCache {
  /// Dernier contenu écrit, ou `null` s'il n'y en a pas.
  Future<String?> read();

  Future<void> write(String json);
}

/// Cache dans un fichier du dossier de support de l'app (non sauvegardé dans
/// les documents de l'utilisateur, conservé entre deux lancements).
class FileDecisionsCache implements DecisionsCache {
  FileDecisionsCache({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  Future<File> get _file async =>
      File('${(await _directory()).path}/decisions_latest.json');

  @override
  Future<String?> read() async {
    final file = await _file;
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> write(String json) async {
    final file = await _file;
    await file.parent.create(recursive: true);
    // Écriture atomique : un fichier à moitié écrit ne remplace jamais le
    // cache précédent.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(file.path);
  }
}
