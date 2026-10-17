import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Liste des 50 derniers scrutins de la 17e législature sur le site de
/// l'Assemblée. Un seul GET par passage : 50 scrutins couvrent largement dix
/// minutes de séance.
const siteListUrl =
    'https://www.assemblee-nationale.fr/dyn/17/scrutins?limit=50';

/// Page d'un scrutin sur le site de l'Assemblée.
String siteScrutinUrl(int numero) =>
    'https://www.assemblee-nationale.fr/dyn/17/scrutins/$numero';

/// User-Agent identifiable envoyé au site de l'Assemblée.
const siteUserAgent =
    'vote-du-jour/1.0 (+https://github.com/lucasangoston/vote-du-jour)';

/// Pages HTML du site de l'Assemblée.
abstract interface class SiteSource {
  /// Page « liste des scrutins ».
  Future<String> fetchList();

  /// Page du scrutin [numero].
  Future<String> fetchScrutin(int numero);
}

/// Lit le site en HTTP, avec un User-Agent identifiable.
class HttpSiteSource implements SiteSource {
  HttpSiteSource({
    this.listUrl = siteListUrl,
    this.scrutinUrl = siteScrutinUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String listUrl;
  final String Function(int numero) scrutinUrl;
  final http.Client _client;

  @override
  Future<String> fetchList() => _get(listUrl);

  @override
  Future<String> fetchScrutin(int numero) => _get(scrutinUrl(numero));

  Future<String> _get(String url) async {
    final response = await _client
        .get(Uri.parse(url), headers: {'user-agent': siteUserAgent})
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('GET $url : HTTP ${response.statusCode}');
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }
}
