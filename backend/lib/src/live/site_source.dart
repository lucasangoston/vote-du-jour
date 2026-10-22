import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Liste des scrutins de la 17e législature sur le site de l'Assemblée, par
/// pages de 50, du plus récent au plus ancien. La page 1 suffit d'ordinaire ;
/// la détection en direct lit les suivantes quand elle ne contient que des
/// scrutins jamais vus (voir `maxListPagesPerPass`).
const siteListUrl =
    'https://www.assemblee-nationale.fr/dyn/17/scrutins?page=1&limit=50';

/// URL de la page [page] (à partir de 1) de la liste [listUrl] : le paramètre
/// `page` est ajouté ou remplacé, les autres sont gardés.
String siteListPageUrl(String listUrl, int page) {
  final uri = Uri.parse(listUrl);
  return uri
      .replace(queryParameters: {...uri.queryParameters, 'page': '$page'})
      .toString();
}

/// Page d'un scrutin sur le site de l'Assemblée.
String siteScrutinUrl(int numero) =>
    'https://www.assemblee-nationale.fr/dyn/17/scrutins/$numero';

/// User-Agent identifiable envoyé au site de l'Assemblée.
const siteUserAgent =
    'vote-du-jour/1.0 (+https://github.com/lucasangoston/vote-du-jour)';

/// Pages HTML du site de l'Assemblée.
abstract interface class SiteSource {
  /// Page [page] (à partir de 1) de la liste des scrutins.
  Future<String> fetchList({int page = 1});

  /// Page du scrutin [numero].
  Future<String> fetchScrutin(int numero);
}

/// Lit le site en HTTP, avec un User-Agent identifiable.
///
/// Comme pour les jeux de données, une connexion coupée, un délai dépassé ou
/// une réponse 5xx est retenté jusqu'à [attempts] fois, à [retryDelay]
/// d'intervalle (plus court que pour les archives : le passage doit tenir
/// dans les 8 minutes du job, même en lisant plusieurs pages de liste).
class HttpSiteSource implements SiteSource {
  HttpSiteSource({
    this.listUrl = siteListUrl,
    this.scrutinUrl = siteScrutinUrl,
    http.Client? client,
    this.attempts = 3,
    this.retryDelay = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final String listUrl;
  final String Function(int numero) scrutinUrl;
  final int attempts;
  final Duration retryDelay;
  final http.Client _client;

  @override
  Future<String> fetchList({int page = 1}) =>
      _get(siteListPageUrl(listUrl, page));

  @override
  Future<String> fetchScrutin(int numero) => _get(scrutinUrl(numero));

  Future<String> _get(String url) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _getOnce(url);
      } on Object catch (e) {
        final transient =
            e is http.ClientException ||
            e is SocketException ||
            e is TimeoutException ||
            e is _ServerError;
        if (!transient || attempt >= attempts) rethrow;
        stderr.writeln(
          "Site de l'Assemblée : $e, nouvel essai ($attempt/$attempts) dans "
          '${retryDelay.inSeconds} s',
        );
        await Future<void>.delayed(retryDelay);
      }
    }
  }

  Future<String> _getOnce(String url) async {
    final response = await _client
        .get(Uri.parse(url), headers: {'user-agent': siteUserAgent})
        .timeout(const Duration(seconds: 30));
    if (response.statusCode >= 500) {
      throw _ServerError('GET $url : HTTP ${response.statusCode}');
    }
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('GET $url : HTTP ${response.statusCode}');
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }
}

/// Réponse 5xx : passagère, retentée.
class _ServerError extends HttpException {
  _ServerError(super.message);
}
