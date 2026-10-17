import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vote_contract/vote_contract.dart';

/// Lit l'index des dernières décisions publié par le job.
class DecisionsRepository {
  DecisionsRepository({required String baseUrl, http.Client? client})
    : _indexUri = Uri.parse(
        baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
      ).resolve(indexPath),
      _client = client ?? http.Client();

  final Uri _indexUri;
  final http.Client _client;

  Future<DecisionIndex> fetchLatest() async {
    final response = await _client
        .get(_indexUri)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw DecisionsUnavailable('HTTP ${response.statusCode}');
    }
    return DecisionIndex.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
  }
}

class DecisionsUnavailable implements Exception {
  const DecisionsUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'DecisionsUnavailable: $reason';
}
