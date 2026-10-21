import 'dart:io';

import 'package:http/http.dart' as http;

/// Archive de l'agenda de la 17e législature (Licence Ouverte) : une réunion
/// par fichier JSON (séances publiques de l'Assemblée et du Sénat, réunions
/// de commission), avec leur ordre du jour. ~8,5 Mo, mise en cache 4 heures
/// par le CDN de l'Assemblée.
const agendaDumpUrl =
    'https://data.assemblee-nationale.fr/static/openData/repository/17/vp/reunions/Agenda.json.zip';

/// Résultat d'une récupération conditionnelle de l'agenda.
sealed class AgendaFetch {
  const AgendaFetch();
}

/// L'agenda n'a pas changé depuis le passage précédent.
class AgendaNotModified extends AgendaFetch {
  const AgendaNotModified();
}

/// Nouvelle version de l'agenda.
class AgendaDownloaded extends AgendaFetch {
  const AgendaDownloaded(this.bytes, {required this.etag});

  final List<int> bytes;

  /// Valeur de l'en-tête `ETag`, à renvoyer dans `If-None-Match`.
  final String? etag;
}

/// Fournit l'archive de l'agenda.
abstract interface class AgendaSource {
  /// Télécharge l'archive, sauf si elle n'a pas changé depuis la version
  /// d'`ETag` [ifNoneMatch] (passage précédent).
  Future<AgendaFetch> fetch({String? ifNoneMatch});
}

/// Télécharge l'archive en HTTP avec une requête conditionnelle
/// (`If-None-Match`).
///
/// Comme pour les autres jeux de données ([HttpDumpSource]), une connexion
/// coupée ou une réponse 5xx est retentée jusqu'à [attempts] fois, à
/// [retryDelay] d'intervalle.
class HttpAgendaSource implements AgendaSource {
  HttpAgendaSource({
    this.url = agendaDumpUrl,
    http.Client? client,
    this.attempts = 3,
    this.retryDelay = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final String url;
  final int attempts;
  final Duration retryDelay;
  final http.Client _client;

  @override
  Future<AgendaFetch> fetch({String? ifNoneMatch}) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _fetchOnce(ifNoneMatch);
      } on Object catch (e) {
        final transient =
            e is http.ClientException ||
            e is SocketException ||
            e is _ServerError;
        if (!transient || attempt >= attempts) rethrow;
        stderr.writeln(
          'Agenda : $e, nouvel essai ($attempt/$attempts) dans '
          '${retryDelay.inSeconds} s',
        );
        await Future<void>.delayed(retryDelay);
      }
    }
  }

  Future<AgendaFetch> _fetchOnce(String? ifNoneMatch) async {
    final response = await _client.get(
      Uri.parse(url),
      headers: {'if-none-match': ?ifNoneMatch},
    );
    if (response.statusCode == HttpStatus.notModified) {
      return const AgendaNotModified();
    }
    if (response.statusCode >= 500) {
      throw _ServerError('GET $url : HTTP ${response.statusCode}');
    }
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('GET $url : HTTP ${response.statusCode}');
    }
    final etag = response.headers['etag'];
    // Un cache intermédiaire peut ignorer If-None-Match : on compare
    // nous-mêmes.
    if (ifNoneMatch != null && etag == ifNoneMatch) {
      return const AgendaNotModified();
    }
    return AgendaDownloaded(response.bodyBytes, etag: etag);
  }
}

/// Réponse 5xx : erreur passagère du serveur, retentée.
class _ServerError extends HttpException {
  _ServerError(super.message);
}

/// Lit l'archive depuis un fichier local (développement) ; sa date de
/// modification tient lieu d'`ETag`.
class FileAgendaSource implements AgendaSource {
  FileAgendaSource(this.path);

  final String path;

  @override
  Future<AgendaFetch> fetch({String? ifNoneMatch}) async {
    final file = File(path);
    final etag = HttpDate.format(await file.lastModified());
    if (etag == ifNoneMatch) return const AgendaNotModified();
    return AgendaDownloaded(await file.readAsBytes(), etag: etag);
  }
}
