import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vote_contract/vote_contract.dart';

import '../config.dart';
import '../decisions_repository.dart' show DecisionsUnavailable;

/// Lit le fichier de détail d'une décision (`v1/decisions/<id>.json`).
class DecisionDetailRepository {
  DecisionDetailRepository({required String baseUrl, http.Client? client})
    : _baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
      _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;

  /// Lève [DecisionsUnavailable] si le fichier n'est pas publié ou si le
  /// réseau est indisponible.
  Future<DecisionDetail> fetch(String id) async {
    final uri = _baseUri.resolve(
      decisionDetailPath(id).split('/').map(Uri.encodeComponent).join('/'),
    );
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw DecisionsUnavailable('HTTP ${response.statusCode}');
    }
    return DecisionDetail.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
  }
}

/// Dépôt par défaut, sur l'URL publique des données ([dataBaseUrl]).
final defaultDecisionDetailRepository = DecisionDetailRepository(
  baseUrl: dataBaseUrl,
);
