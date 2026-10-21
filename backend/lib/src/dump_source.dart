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
///
/// Le serveur de l'Assemblée coupe parfois la connexion en plein
/// téléchargement ou répond 5xx : la requête est alors retentée jusqu'à
/// [attempts] fois, à [retryDelay] d'intervalle.
class HttpDumpSource implements DumpSource {
  HttpDumpSource({
    this.url = scrutinsDumpUrl,
    http.Client? client,
    this.attempts = 3,
    this.retryDelay = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final String url;
  final int attempts;
  final Duration retryDelay;
  final http.Client _client;

  @override
  Future<DumpFetch> fetch({String? ifModifiedSince}) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _fetchOnce(ifModifiedSince);
      } on Object catch (e) {
        if (!_isTransient(e) || attempt >= attempts) rethrow;
        stderr.writeln(
          'Archive des scrutins : $e, nouvel essai '
          '($attempt/$attempts) dans ${retryDelay.inSeconds} s',
        );
        await Future<void>.delayed(retryDelay);
      }
    }
  }

  static bool _isTransient(Object e) =>
      e is http.ClientException || e is SocketException || e is _ServerError;

  Future<DumpFetch> _fetchOnce(String? ifModifiedSince) async {
    final response = await _client.get(
      Uri.parse(url),
      headers: {'if-modified-since': ?ifModifiedSince},
    );
    if (response.statusCode == HttpStatus.notModified) {
      return const DumpNotModified();
    }
    if (response.statusCode >= 500) {
      throw _ServerError('GET $url : HTTP ${response.statusCode}');
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

/// Réponse 5xx : erreur passagère du serveur, retentée.
class _ServerError extends HttpException {
  _ServerError(super.message);
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
