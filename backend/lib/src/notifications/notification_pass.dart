import 'dart:convert';

import 'package:vote_contract/vote_contract.dart';

import '../dossier_index.dart' show Lecture;
import '../live/live_state.dart';
import '../object_store.dart';
import 'eve_notification.dart';
import 'fcm_client.dart';

/// Mémoire des notifications envoyées, dans le bucket.
const notificationsStateKey = 'state/notifications.json';

/// Sujet FCM auquel l'app abonne les utilisateurs qui veulent être prévenus
/// des votes importants.
const importantVotesTopic = 'votes-importants';

/// Au plus autant de notifications par passage ; les suivantes partent aux
/// passages suivants.
const maxNotificationsPerPass = 3;

/// Une décision plus ancienne n'est plus notifiée (job longtemps arrêté,
/// étape corrigée après coup par un nouveau jeu de données…).
const notificationMaxAge = Duration(days: 7);

/// Étapes qui rendent un vote sur un texte important.
final _importantLectures = [
  Lecture.definitive,
  Lecture.commissionMixteParitaire,
];

/// La décision [d] est-elle un vote important, à notifier (#34) ?
///
/// - scrutin public solennel ([codeTypeVote] `SPS`) ;
/// - motion de censure (type, ou code `MOC`) ;
/// - texte en lecture définitive ou texte de compromis (CMP), adopté ou
///   rejeté.
///
/// Jamais : vote à main levée, proposition de résolution, décision
/// provisoire (elle est notifiée à sa confirmation, pour ne jamais annoncer
/// un résultat faux).
///
/// [codeTypeVote] vient du jeu de données (`state/scrutins-confirmes.json`) :
/// l'index publié ne dit pas si un scrutin est solennel.
bool isImportantDecision(DecisionSummary d, {String? codeTypeVote}) {
  if (d.status != DecisionStatus.confirmee) return false;
  if (d.voteMode != VoteMode.scrutinPublic) return false;
  if (d.type == DecisionType.resolution) return false;
  if (codeTypeVote == 'SPS' || codeTypeVote == 'MOC') return true;
  if (d.type == DecisionType.motionDeCensure) return true;
  final stage = d.stage;
  return stage != null &&
      (d.type == DecisionType.ensembleTexte ||
          d.type == DecisionType.rejetPrealable) &&
      _importantLectures.any((l) => stage.endsWith(l.label));
}

/// Lien profond vers le détail de la décision [id], déjà géré par l'app
/// (`decisionIdFromDeepLink`).
String decisionDeepLink(String id) =>
    'votedujour://decisions/${Uri.encodeComponent(id)}';

/// Notification de la décision [d] : « Adopté : titre » ou « Rejeté :
/// titre », la phrase d'explication du résumé en corps (sinon l'étape),
/// l'identifiant et le lien profond en données.
PushMessage notificationFor(DecisionSummary d) {
  final verdict = switch (d.result) {
    VoteResult.adopte => 'Adopté',
    VoteResult.rejete => 'Rejeté',
  };
  return PushMessage(
    topic: importantVotesTopic,
    title: '$verdict : ${_shorten(d.displayTitle, 120)}',
    body: d.explanation ?? d.stage ?? '',
    data: {'decisionId': d.id, 'link': decisionDeepLink(d.id)},
  );
}

String _shorten(String s, int max) {
  final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.length <= max ? t : '${t.substring(0, max - 1).trimRight()}…';
}

/// Une annonce de la veille plus ancienne est oubliée.
const _eveRetention = Duration(days: 30);

/// Contenu de [notificationsStateKey] : les décisions déjà notifiées, avec
/// la date d'envoi (ou de mise en service, pour celles déjà publiées avant),
/// et les votes solennels déjà annoncés la veille.
class NotificationState {
  NotificationState({
    required this.initializedAt,
    Map<String, String>? sent,
    Map<String, String>? eve,
  }) : sent = sent ?? {},
       eve = eve ?? {};

  /// Premier passage : les décisions publiées à ce moment-là ne sont pas
  /// notifiées.
  final DateTime initializedAt;

  /// Identifiant de décision → date d'envoi (ISO 8601) ou `initial`.
  final Map<String, String> sent;

  /// Votes solennels annoncés la veille (#54) : clé
  /// [eveNotificationKey] → date d'envoi (ISO 8601) ou `initial`. Absent
  /// des mémoires écrites avant #54 : vide.
  final Map<String, String> eve;

  static const _version = 1;

  static const initialMark = 'initial';

  Map<String, Object?> toJson() => {
    'version': _version,
    'initializedAt': initializedAt.toUtc().toIso8601String(),
    'sent': sent,
    'eve': eve,
  };

  static NotificationState fromJson(Object? json) {
    final initializedAt = json is Map<String, Object?>
        ? DateTime.tryParse('${json['initializedAt']}')
        : null;
    final sent = json is Map<String, Object?> ? json['sent'] : null;
    final eve = json is Map<String, Object?>
        ? json['eve'] ?? const <String, Object?>{}
        : null;
    if (json is! Map<String, Object?> ||
        json['version'] != _version ||
        initializedAt == null ||
        sent is! Map<String, Object?> ||
        sent.values.any((v) => v is! String) ||
        eve is! Map<String, Object?> ||
        eve.values.any((v) => v is! String)) {
      throw const FormatException(
        'Mémoire des notifications : format inattendu',
      );
    }
    return NotificationState(
      initializedAt: initializedAt,
      sent: sent.cast<String, String>(),
      eve: Map.of(eve.cast<String, String>()),
    );
  }

  Future<void> write(ObjectStore store) => store.write(
    notificationsStateKey,
    const JsonEncoder.withIndent('  ').convert(toJson()),
    cacheControl: 'no-store',
  );
}

/// Bilan d'un passage des notifications.
class NotificationReport {
  /// Décisions notifiées pendant ce passage.
  final sent = <String>[];

  /// Votes solennels du lendemain annoncés pendant ce passage
  /// (identifiants des points).
  final eveSent = <String>[];

  /// Premier passage : décisions déjà publiées, marquées comme notifiées
  /// sans envoi ; `null` sinon.
  int? initialized;

  /// Décisions importantes et annonces de la veille reportées au passage
  /// suivant (plafond atteint).
  var deferred = 0;

  final warnings = <String>[];

  @override
  String toString() => [
    if (initialized case final n?)
      'Notifications : mise en service, $n décisions et votes à venir déjà '
          'publiés marqués comme notifiés, aucun envoi.'
    else
      'Notifications : ${sent.length} envoyées'
          '${sent.isEmpty ? '' : ' (${sent.join(', ')})'}'
          ', ${eveSent.length} annonces de la veille'
          '${eveSent.isEmpty ? '' : ' (${eveSent.join(', ')})'}'
          '${deferred == 0 ? '' : ', $deferred reportées au passage suivant'}.',
    ...warnings.map((w) => 'Attention : $w'),
  ].join('\n');
}

/// Un passage des notifications, sur l'index publié ([indexPath]) : chaque
/// décision importante ([isImportantDecision]) pas encore notifiée, de la
/// plus ancienne à la plus récente, est envoyée au sujet
/// [importantVotesTopic] par [sender], au plus [maxNotificationsPerPass]
/// fois par passage.
///
/// La mémoire ([notificationsStateKey]) est écrite après chaque envoi
/// réussi : une décision n'est jamais notifiée deux fois. Un envoi qui
/// échoue est retenté au passage suivant. Au premier passage (mémoire
/// absente ou illisible), les décisions de l'index sont marquées comme
/// notifiées sans rien envoyer.
///
/// Le même passage annonce, le soir, les votes solennels du lendemain
/// (#54, [isEveNotificationDue]) d'après le bloc « À venir » de l'index,
/// recalculé juste avant par le passage de l'agenda : un point supprimé ou
/// reporté n'y figure plus à cette date. Une annonce par point
/// ([eveNotificationKey]), avant les décisions (elle ne vaut que ce
/// soir-là), sous le même plafond. Si l'agenda n'a pas pu être relu à ce
/// passage ([agendaUpToDate] faux), aucune annonce : le bloc peut être
/// périmé ; un passage suivant de la soirée s'en charge.
///
/// À lancer après la publication, les résumés et l'agenda, pour que la
/// notification porte la phrase d'explication ; jamais depuis la détection
/// en direct.
Future<NotificationReport> runNotificationPass({
  required ObjectStore store,
  required PushSender sender,
  DateTime Function() clock = DateTime.now,
  bool agendaUpToDate = true,
}) async {
  final report = NotificationReport();
  final now = clock().toUtc();
  final DecisionIndex index;
  try {
    final raw = await store.read(indexPath);
    if (raw == null) {
      report.warnings.add('index absent, notifications reportées');
      return report;
    }
    index = DecisionIndex.fromJson(jsonDecode(raw));
  } on Object catch (e) {
    report.warnings.add('index illisible, notifications reportées ($e)');
    return report;
  }

  NotificationState? state;
  try {
    final raw = await store.read(notificationsStateKey);
    if (raw != null) state = NotificationState.fromJson(jsonDecode(raw));
  } on Object catch (e) {
    report.warnings.add(
      'mémoire des notifications illisible, réinitialisée sans envoi ($e)',
    );
  }
  if (state == null) {
    final initial = NotificationState(
      initializedAt: now,
      sent: {
        for (final d in index.decisions) d.id: NotificationState.initialMark,
      },
      eve: {
        for (final u in index.upcoming ?? const <UpcomingItem>[])
          if (u.kind == UpcomingKind.voteSolennel)
            eveNotificationKey(u): NotificationState.initialMark,
      },
    );
    await initial.write(store);
    report.initialized = initial.sent.length + initial.eve.length;
    return report;
  }

  // Annonces de la veille oubliées après [_eveRetention].
  final remembered = state.eve.length;
  state.eve.removeWhere((_, at) {
    final date = at == NotificationState.initialMark
        ? state!.initializedAt
        : DateTime.tryParse(at);
    return date == null || now.difference(date) > _eveRetention;
  });
  if (state.eve.length != remembered) await state.write(store);

  final eve = [
    for (final u in index.upcoming ?? const <UpcomingItem>[])
      if (isEveNotificationDue(u, now) &&
          !state.eve.containsKey(eveNotificationKey(u)))
        u,
  ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  if (eve.isNotEmpty && !agendaUpToDate) {
    report.warnings.add(
      'agenda non relu à ce passage : ${eve.length} annonces de la veille '
      'reportées',
    );
    eve.clear();
  }

  var attempts = 0;
  for (final u in eve) {
    if (attempts >= maxNotificationsPerPass) {
      report.deferred++;
      continue;
    }
    attempts++;
    try {
      await sender.send(eveNotificationFor(u, topic: importantVotesTopic));
    } on Object catch (e) {
      report.warnings.add('annonce de la veille ${u.id} non envoyée ($e)');
      continue;
    }
    state.eve[eveNotificationKey(u)] = now.toIso8601String();
    await state.write(store);
    report.eveSent.add(u.id);
  }

  // Type de vote (solennel…) des scrutins du jeu de données.
  final snapshot = await ConfirmedSnapshot.read(store, report.warnings);
  if (snapshot == null) {
    report.warnings.add(
      'instantané des scrutins absent : scrutins solennels non repérés',
    );
  }
  final codes = {
    for (final s in snapshot?.scrutins ?? const []) s.uid: s.codeTypeVote,
  };

  final oldest = now.subtract(notificationMaxAge);
  final candidates =
      [
        for (final d in index.decisions)
          if (!state.sent.containsKey(d.id) &&
              !d.date.isBefore(oldest) &&
              isImportantDecision(d, codeTypeVote: codes[d.id]))
            d,
      ]..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : (a.numero ?? 0).compareTo(b.numero ?? 0);
      });

  for (final d in candidates) {
    if (attempts >= maxNotificationsPerPass) {
      report.deferred++;
      continue;
    }
    attempts++;
    try {
      await sender.send(notificationFor(d));
    } on Object catch (e) {
      report.warnings.add('notification de ${d.id} non envoyée ($e)');
      continue;
    }
    state.sent[d.id] = now.toIso8601String();
    await state.write(store);
    report.sent.add(d.id);
  }
  return report;
}
