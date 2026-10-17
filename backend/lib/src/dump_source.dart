import 'dart:io';

import 'package:http/http.dart' as http;

/// Archive des scrutins de la 17e législature (Licence Ouverte), régénérée
/// une fois par jour vers 12h30, heure de Paris.
const scrutinsDumpUrl =
    'https://data.assemblee-nationale.fr/static/openData/repository/17/loi/scrutins/Scrutins.json.zip';

/// Résultat d'une récupération conditionnelle du jeu de données.
sealed class DumpFetch {
  const DumpFetch();
}

/// Le jeu de données n'a pas changé depuis la dernière exécution.
class DumpNotModified extends DumpFetch {
  const DumpNotModified();
}

/// Nouvelle version du jeu de données.
class DumpDownloaded extends DumpFetch {
  const DumpDownloaded(this.bytes, {required this.lastModified});

  final List<int> bytes;

  /// Valeur de l'en-tête `Last-Modified`, à renvoyer dans `If-Modified-Since`.
  final String? lastModified;
}

/// Fournit l'archive des scrutins.
abstract interface class DumpSource {
  /// Télécharge l'archive, sauf si elle n'a pas changé depuis
  /// [ifModifiedSince] (valeur `Last-Modified` d'une exécution précédente).
  Future<DumpFetch> fetch({String? ifModifiedSince});
}

/// Télécharge l'archive en HTTP avec une requête conditionnelle.
class HttpDumpSource implements DumpSource {
  HttpDumpSource({this.url = scrutinsDumpUrl, http.Client? client})
    : _client = client ?? http.Client();

  final String url;
  final http.Client _client;

  @override
  Future<DumpFetch> fetch({String? ifModifiedSince}) async {
    final response = await _client.get(
      Uri.parse(url),
      headers: {'if-modified-since': ?ifModifiedSince},
    );
    if (response.statusCode == HttpStatus.notModified) {
      return const DumpNotModified();
    }
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('GET $url : HTTP ${response.statusCode}');
    }
    final lastModified = response.headers['last-modified'];
    // Certains serveurs ignorent If-Modified-Since : on compare nous-mêmes.
    if (ifModifiedSince != null && lastModified == ifModifiedSince) {
      return const DumpNotModified();
    }
    return DumpDownloaded(response.bodyBytes, lastModified: lastModified);
  }
}

/// Lit l'archive depuis un fichier local (développement).
class FileDumpSource implements DumpSource {
  FileDumpSource(this.path);

  final String path;

  @override
  Future<DumpFetch> fetch({String? ifModifiedSince}) async {
    final file = File(path);
    final lastModified = HttpDate.format(await file.lastModified());
    if (lastModified == ifModifiedSince) return const DumpNotModified();
    return DumpDownloaded(await file.readAsBytes(), lastModified: lastModified);
  }
}
