import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:vote_contract/vote_contract.dart';

import 'decisions_cache.dart';

/// Lit l'index des dernières décisions publié par le job.
///
/// Avec un [DecisionsCache], chaque index téléchargé est gardé pour être
/// relu hors ligne avec [readCached].
class DecisionsRepository {
  DecisionsRepository({
    required String baseUrl,
    http.Client? client,
    DecisionsCache? cache,
  }) : _indexUri = Uri.parse(
         baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
       ).resolve(indexPath),
       _client = client ?? http.Client(),
       _cache = cache;

  final Uri _indexUri;
  final http.Client _client;
  final DecisionsCache? _cache;

  Future<DecisionIndex> fetchLatest() async {
    final response = await _client
        .get(_indexUri)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw DecisionsUnavailable('HTTP ${response.statusCode}');
    }
    final body = utf8.decode(response.bodyBytes);
    final index = DecisionIndex.fromJson(jsonDecode(body));
    // Seul un index lisible remplace le cache.
    try {
      await _cache?.write(body);
    } catch (e) {
      debugPrint('DecisionsRepository : écriture du cache impossible : $e');
    }
    return index;
  }

  /// Dernier index téléchargé avec succès, ou `null` s'il n'y en a pas ou
  /// s'il est illisible (format d'une autre version de l'app, par exemple).
  Future<DecisionIndex?> readCached() async {
    try {
      final json = await _cache?.read();
      return json == null ? null : DecisionIndex.fromJson(jsonDecode(json));
    } catch (e) {
      debugPrint('DecisionsRepository : cache illisible : $e');
      return null;
    }
  }
}

class DecisionsUnavailable implements Exception {
  const DecisionsUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'DecisionsUnavailable: $reason';
}
