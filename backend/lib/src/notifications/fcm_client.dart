import 'dart:convert';

import 'package:http/http.dart' as http;

import 'rs256.dart';

/// Portée OAuth2 de l'envoi de messages Firebase Cloud Messaging.
const fcmScope = 'https://www.googleapis.com/auth/firebase.messaging';

/// Notification push à envoyer à tous les appareils abonnés à un sujet.
class PushMessage {
  const PushMessage({
    required this.topic,
    required this.title,
    required this.body,
    this.data = const {},
  });

  final String topic;
  final String title;
  final String body;

  /// Données transmises à l'app avec la notification (valeurs texte).
  final Map<String, String> data;

  /// Corps de la requête FCM HTTP v1 (`messages:send`) : notification
  /// affichée par le système, son par défaut sur Android et iOS.
  Map<String, Object?> toFcmJson() => {
    'message': {
      'topic': topic,
      'notification': {'title': title, 'body': body},
      'data': data,
      'android': {
        'notification': {'sound': 'default'},
      },
      'apns': {
        'payload': {
          'aps': {'sound': 'default'},
        },
      },
    },
  };
}

/// Envoie des notifications push.
abstract interface class PushSender {
  /// Envoie [message] ; lève une exception en cas d'échec.
  Future<void> send(PushMessage message);
}

/// Compte de service Google (clé JSON téléchargée depuis la console
/// Firebase), qui autorise l'envoi des notifications.
class ServiceAccount {
  const ServiceAccount({
    required this.projectId,
    required this.clientEmail,
    required this.privateKey,
    this.privateKeyId,
    this.tokenUri = 'https://oauth2.googleapis.com/token',
  });

  /// Lit la clé JSON du compte de service ; lève [FormatException] si elle
  /// est illisible ou incomplète.
  factory ServiceAccount.fromJson(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('Compte de service : JSON illisible');
    }
    if (json is! Map<String, Object?>) {
      throw const FormatException('Compte de service : objet JSON attendu');
    }
    final fields = json;
    String field(String name) {
      final value = fields[name];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Compte de service : champ $name manquant');
      }
      return value;
    }

    final tokenUri = fields['token_uri'];
    final keyId = fields['private_key_id'];
    return ServiceAccount(
      projectId: field('project_id'),
      clientEmail: field('client_email'),
      privateKey: RsaPrivateKey.fromPem(field('private_key')),
      privateKeyId: keyId is String && keyId.isNotEmpty ? keyId : null,
      tokenUri: tokenUri is String && tokenUri.isNotEmpty
          ? tokenUri
          : 'https://oauth2.googleapis.com/token',
    );
  }

  final String projectId;
  final String clientEmail;
  final RsaPrivateKey privateKey;
  final String? privateKeyId;
  final String tokenUri;

  /// Assertion JWT à échanger contre un jeton d'accès (OAuth2 pour les
  /// comptes de service, RFC 7523), valable une heure à partir de [now].
  String assertion(DateTime now) {
    final iat = now.millisecondsSinceEpoch ~/ 1000;
    return signJwtRs256(
      keyId: privateKeyId,
      key: privateKey,
      claims: {
        'iss': clientEmail,
        'scope': fcmScope,
        'aud': tokenUri,
        'iat': iat,
        'exp': iat + 3600,
      },
    );
  }
}

/// Client FCM HTTP v1 : obtient un jeton d'accès à partir du compte de
/// service (une fois par exécution), puis envoie chaque message.
class FcmClient implements PushSender {
  FcmClient({
    required this.account,
    http.Client? client,
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  final ServiceAccount account;
  final http.Client _client;
  final DateTime Function() _clock;
  Future<String>? _token;

  Uri get _sendUri => Uri.https(
    'fcm.googleapis.com',
    '/v1/projects/${account.projectId}/messages:send',
  );

  Future<String> _accessToken() async {
    final response = await _client.post(
      Uri.parse(account.tokenUri),
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': account.assertion(_clock()),
      },
    );
    if (response.statusCode != 200) {
      throw FcmException(
        'jeton OAuth2 refusé (HTTP ${response.statusCode}) : '
        '${_excerpt(response.body)}',
      );
    }
    final json = jsonDecode(response.body);
    final token = json is Map ? json['access_token'] : null;
    if (token is! String || token.isEmpty) {
      throw const FcmException('réponse OAuth2 sans access_token');
    }
    return token;
  }

  @override
  Future<void> send(PushMessage message) async {
    final Future<String> token;
    try {
      token = _token ??= _accessToken();
      await token;
    } on Object {
      // Un échec n'est pas mémorisé : le prochain envoi réessaie.
      _token = null;
      rethrow;
    }
    final response = await _client.post(
      _sendUri,
      headers: {
        'authorization': 'Bearer ${await token}',
        'content-type': 'application/json; charset=utf-8',
      },
      body: jsonEncode(message.toFcmJson()),
    );
    if (response.statusCode != 200) {
      throw FcmException(
        'envoi refusé (HTTP ${response.statusCode}) : '
        '${_excerpt(response.body)}',
      );
    }
  }
}

String _excerpt(String body) =>
    body.length <= 300 ? body : '${body.substring(0, 300)}…';

class FcmException implements Exception {
  const FcmException(this.message);

  final String message;

  @override
  String toString() => 'FCM : $message';
}
