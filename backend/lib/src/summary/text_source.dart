import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Page HTML d'un texte de l'Assemblée (dépôt, texte adopté…) par
/// identifiant de document.
String legislativeTextUrl(String textUid) =>
    'https://www.assemblee-nationale.fr/dyn/opendata/$textUid.html';

/// Résultat de la récupération d'un texte.
sealed class TextFetch {
  const TextFetch();
}

/// La page du texte.
class TextFound extends TextFetch {
  const TextFound(this.html);

  final String html;
}

/// Le texte n'est pas (encore) en ligne, ou le site est injoignable.
class TextUnavailable extends TextFetch {
  const TextUnavailable(this.reason);

  final String reason;
}

/// Source des textes officiels (le site de l'Assemblée en production, des
/// fixtures dans les tests).
abstract interface class LegislativeTextSource {
  Future<TextFetch> fetch(String textUid);
}

/// Lit les textes sur le site de l'Assemblée : un GET par texte, sans
/// jamais faire échouer le job (une erreur vaut texte indisponible).
class HttpLegislativeTextSource implements LegislativeTextSource {
  HttpLegislativeTextSource({
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  @override
  Future<TextFetch> fetch(String textUid) async {
    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(textUid)) {
      return TextUnavailable('identifiant de texte inattendu : $textUid');
    }
    try {
      final response = await _client
          .get(
            Uri.parse(legislativeTextUrl(textUid)),
            headers: {'user-agent': 'vote-du-jour/1.0'},
          )
          .timeout(timeout);
      if (response.statusCode != 200) {
        return TextUnavailable('HTTP ${response.statusCode}');
      }
      return TextFound(utf8.decode(response.bodyBytes, allowMalformed: true));
    } on Exception catch (e) {
      return TextUnavailable('$e');
    }
  }
}
