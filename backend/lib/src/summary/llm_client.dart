import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vote_contract/vote_contract.dart';

import 'source_text.dart';
import 'summary_prompt.dart';

/// Modèle utilisé pour les résumés : Claude Haiku 5.5.
const summaryModel = 'claude-haiku-5-5';

/// Plafond de jetons de sortie, réflexion comprise (Claude Haiku 5.5 réfléchit
/// par défaut) : large devant un résumé d'environ 300 jetons.
const summaryMaxTokens = 4096;

/// Effort de réflexion. `medium` est la valeur par défaut de Claude Haiku
/// 5.5, fixée explicitement : la tâche est simple mais la consigne de
/// neutralité doit être suivie à la lettre.
const summaryEffort = 'medium';

/// Client de l'API Messages : reçoit le corps de la requête, renvoie le corps
/// JSON de la réponse. Un faux client le remplace dans les tests : aucun
/// test n'appelle l'API.
abstract interface class LlmClient {
  /// Lève [LlmException] si l'appel échoue (HTTP, réseau, délai).
  Future<Map<String, Object?>> createMessage(Map<String, Object?> request);
}

/// Échec d'un appel au modèle ou réponse inutilisable. La décision est
/// marquée « à régénérer ».
class LlmException implements Exception {
  const LlmException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Appelle l'API Messages d'Anthropic en HTTP (pas de SDK officiel en
/// Dart). La clé n'apparaît dans aucun message d'erreur.
class AnthropicClient implements LlmClient {
  AnthropicClient({
    required String apiKey,
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
  }) : _apiKey = apiKey,
       _client = client ?? http.Client();

  static final _endpoint = Uri.parse('https://api.anthropic.com/v1/messages');

  final String _apiKey;
  final http.Client _client;
  final Duration timeout;

  @override
  Future<Map<String, Object?>> createMessage(
    Map<String, Object?> request,
  ) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            _endpoint,
            headers: {
              'content-type': 'application/json',
              'x-api-key': _apiKey,
              'anthropic-version': '2023-06-01',
            },
            body: jsonEncode(request),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const LlmException('API Anthropic : délai dépassé');
    } on Exception catch (e) {
      throw LlmException('API Anthropic injoignable (${e.runtimeType})');
    }
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode != 200) {
      throw LlmException(
        'API Anthropic : HTTP ${response.statusCode} ${_errorMessage(body)}',
      );
    }
    try {
      final json = jsonDecode(body);
      if (json is Map<String, Object?>) return json;
    } on FormatException {
      // Traité ci-dessous.
    }
    throw const LlmException('API Anthropic : réponse JSON illisible');
  }

  /// Type et message d'erreur de l'API (`{"error": {"type", "message"}}`).
  static String _errorMessage(String body) {
    try {
      final error = (jsonDecode(body) as Map)['error'] as Map;
      return '${error['type']} : ${error['message']}';
    } on Object {
      return body.length > 200 ? '${body.substring(0, 200)}…' : body;
    }
  }
}

/// Corps de la requête à l'API Messages pour résumer [decision] à partir de
/// [source] (`null` : intitulé seul).
///
/// Sortie structurée (`output_config.format`, schéma JSON) ; pas de
/// `temperature` (refusée par Claude Haiku 5.5 hors valeur par défaut) ;
/// réflexion adaptative, active par défaut.
Map<String, Object?> buildSummaryRequest({
  required DecisionSummary decision,
  SourceText? source,
}) => {
  'model': summaryModel,
  'max_tokens': summaryMaxTokens,
  'system': summarySystemPrompt,
  'messages': [
    {
      'role': 'user',
      'content': buildSummaryUserMessage(decision: decision, source: source),
    },
  ],
  'output_config': {
    'effort': summaryEffort,
    'format': {'type': 'json_schema', 'schema': summaryOutputSchema},
  },
};

/// Lit la réponse du modèle (corps JSON de l'API Messages) et vérifie le
/// résumé.
///
/// [withPoints] : le texte source a été fourni, 3 ou 4 points sont
/// attendus (au-delà de 4, seuls les 4 premiers sont gardés) ; sinon les
/// points sont ignorés. Lève [LlmException] si la réponse est un refus,
/// est coupée, ou ne respecte pas le format.
PlainSummary parseSummaryResponse(
  Map<String, Object?> response, {
  required bool withPoints,
}) {
  final stopReason = response['stop_reason'];
  if (stopReason == 'refusal') {
    throw const LlmException('le modèle a refusé de répondre');
  }
  if (stopReason != 'end_turn') {
    throw LlmException('réponse interrompue (stop_reason : $stopReason)');
  }
  // La réponse peut commencer par des blocs de réflexion : seuls les blocs
  // de texte comptent.
  final content = response['content'];
  final text = StringBuffer();
  if (content is List) {
    for (final block in content) {
      if (block is Map && block['type'] == 'text' && block['text'] is String) {
        text.write(block['text']);
      }
    }
  }
  final Object? json;
  try {
    json = jsonDecode(text.toString());
  } on FormatException {
    throw const LlmException('réponse du modèle : JSON illisible');
  }
  if (json is! Map<String, Object?>) {
    throw const LlmException('réponse du modèle : objet JSON attendu');
  }
  final title = _clean(json['title']);
  final explanation = _clean(json['explanation']);
  if (title == null || title.length > 120) {
    throw const LlmException('réponse du modèle : titre absent ou trop long');
  }
  if (explanation == null || explanation.length > 400) {
    throw const LlmException(
      'réponse du modèle : explication absente ou trop longue',
    );
  }
  final rawPoints = json['points'];
  final points = [
    if (rawPoints is List)
      for (final p in rawPoints) ?_clean(p),
  ];
  if (withPoints && points.length < 3) {
    throw LlmException(
      'réponse du modèle : ${points.length} points, 3 ou 4 attendus',
    );
  }
  return PlainSummary(
    title: title.endsWith('.') && !title.endsWith('...')
        ? title.substring(0, title.length - 1)
        : title,
    explanation: explanation,
    points: withPoints ? points.take(4).toList() : const [],
    promptVersion: summaryPromptVersion,
  );
}

String? _clean(Object? value) {
  if (value is! String) return null;
  final s = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s.isEmpty ? null : s;
}
