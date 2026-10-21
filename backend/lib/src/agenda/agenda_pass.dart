import 'dart:convert';

import 'package:vote_contract/vote_contract.dart';

import '../dossier_index.dart';
import '../job.dart' show dossiersStateKey, indexCacheControl;
import '../object_store.dart';
import 'agenda_reader.dart';
import 'agenda_source.dart';

/// Clé de l'état de l'agenda dans le bucket.
const agendaStateKey = 'state/agenda.json';

/// Les discussions de texte sont annoncées sur une semaine.
const upcomingHorizon = Duration(days: 7);

/// Les votes solennels, rares et fixés longtemps à l'avance par la
/// Conférence des présidents, sont annoncés sur deux semaines : le prochain
/// vote d'un texte budgétaire tombe souvent au-delà d'une semaine.
const upcomingVoteHorizon = Duration(days: 14);

/// Une séance finie depuis plus longtemps n'est plus gardée dans l'état.
const _stateRetention = Duration(days: 1);

/// Bilan d'un passage.
class AgendaReport {
  AgendaReport();

  /// L'agenda a été téléchargé (il avait changé).
  bool downloaded = false;

  /// L'agenda a été relu à ce passage (téléchargé, ou inchangé d'après son
  /// `ETag`) : les points de l'état sont à jour. Faux après une panne.
  bool upToDate = false;

  /// Points retenus dans l'état (séances pas encore finies).
  int points = 0;

  /// Fichiers de l'agenda illisibles, ignorés.
  int unreadable = 0;

  /// Bloc publié ; `null` si l'index n'a pas été touché.
  List<UpcomingItem>? upcoming;

  /// L'index a été réécrit (le bloc avait changé).
  bool written = false;

  final warnings = <String>[];

  @override
  String toString() => [
    'Agenda : ${upcoming == null ? 'bloc « À venir » inchangé' : '${upcoming!.length} points à venir'}'
        '${written ? ', index réécrit' : ''} ; agenda '
        '${downloaded ? 'téléchargé' : 'inchangé'}, $points points retenus'
        '${unreadable > 0 ? ', $unreadable fichiers illisibles' : ''}.',
    for (final u in upcoming ?? const <UpcomingItem>[])
      '  ${u.startsAt.toIso8601String()} ${u.kind.json}'
          '${u.inProgress ? ' (suite)' : ''} ${u.shortTitle}'
          ' [${u.dossierRef ?? 'sans dossier'}]',
    ...warnings.map((w) => 'Attention : $w'),
  ].join('\n');
}

/// Un passage, après la publication de l'index par le job :
///
/// 1. l'agenda n'est téléchargé que s'il a changé (`If-None-Match` avec
///    l'`ETag` de l'état `state/agenda.json`) ; il est alors relu
///    ([readAgendaArchive]) et ses points remplacent ceux de l'état : un
///    point passé à « Supprimé » disparaît ;
/// 2. le bloc `upcoming` de l'index est recalculé à chaque passage à partir
///    des points de l'état ([buildUpcoming]), même si l'agenda n'a pas
///    changé : la fenêtre avance et les titres des décisions publiées
///    peuvent avoir changé ;
/// 3. l'index n'est réécrit que si le bloc a changé.
///
/// Une panne de l'agenda (serveur indisponible, archive illisible) n'empêche
/// rien : avertissement, et bloc recalculé à partir du dernier agenda connu
/// (à défaut, l'index publié est laissé tel quel). [force] ignore l'`ETag`.
Future<AgendaReport> runAgendaPass({
  required ObjectStore store,
  required AgendaSource source,
  DateTime Function() clock = DateTime.now,
  bool force = false,
}) async {
  final report = AgendaReport();
  final now = clock().toUtc();
  final previous = await AgendaState.read(store, report.warnings);
  AgendaState? state = previous;
  try {
    final fetch = await source.fetch(
      ifNoneMatch: force ? null : previous?.etag,
    );
    if (fetch case AgendaDownloaded(:final bytes, :final etag)) {
      final read = readAgendaArchive(
        bytes,
        since: now.subtract(_stateRetention),
      );
      report
        ..downloaded = true
        ..unreadable = read.unreadable;
      state = AgendaState(etag: etag, fetchedAt: now, points: read.points);
    }
    report.upToDate = true;
  } on Object catch (e) {
    report.warnings.add(
      previous == null
          ? 'agenda indisponible, bloc « À venir » publié inchangé ($e)'
          : 'agenda indisponible, dernier agenda connu utilisé ($e)',
    );
  }
  if (state == null) return report;
  report.points = state.points.length;

  final raw = await store.read(indexPath);
  if (raw == null) {
    report.warnings.add('pas d\'index publié, bloc « À venir » reporté');
    return report;
  }
  final DecisionIndex index;
  try {
    index = DecisionIndex.fromJson(jsonDecode(raw));
  } on Object catch (e) {
    report.warnings.add(
      'index publié illisible, bloc « À venir » reporté ($e)',
    );
    return report;
  }

  final upcoming = buildUpcoming(
    state.points,
    now: now,
    decisions: index.decisions,
    dossiers: await _readDossiers(store),
  );
  report.upcoming = upcoming;
  if (_encode(upcoming) != _encode(index.upcoming)) {
    await store.write(
      indexPath,
      const JsonEncoder.withIndent(
        '  ',
      ).convert(index.withUpcoming(upcoming).toJson()),
      cacheControl: indexCacheControl,
    );
    report.written = true;
  }
  // L'état après l'index : si l'écriture de l'index échoue, le passage
  // suivant retélécharge l'agenda.
  if (!identical(state, previous)) await state.write(store);
  return report;
}

String _encode(List<UpcomingItem>? items) =>
    jsonEncode(items?.map((u) => u.toJson()).toList());

/// Le bloc `upcoming` à l'instant [now], à partir des points de l'agenda
/// [points] (dans l'ordre de [readAgendaArchive]) :
///
/// - points des séances pas encore finies, qui commencent dans les
///   [upcomingHorizon] (discussions) ou [upcomingVoteHorizon] (votes) ;
/// - un seul point par texte et par nature, le premier : plusieurs séances
///   de discussion du même texte font un seul point, en cours
///   ([UpcomingItem.inProgress]) si la première séance n'est qu'une « suite
///   de la discussion » ;
/// - titre court : celui de la décision publiée la plus récente du même
///   dossier (titre du résumé, sinon titre court, [decisions]), sinon le
///   titre du dossier ([dossiers]), sinon le libellé sans formule de
///   procédure ([cleanLabel]). Une précision du libellé entre parenthèses
///   (« (première partie) ») est ajoutée au titre d'un vote. Aucun appel au
///   modèle.
List<UpcomingItem> buildUpcoming(
  List<AgendaPoint> points, {
  required DateTime now,
  List<DecisionSummary> decisions = const [],
  DossierIndex? dossiers,
}) {
  final seen = <String>{};
  final items = <UpcomingItem>[];
  for (final p in points) {
    final horizon = p.kind == UpcomingKind.voteSolennel
        ? upcomingVoteHorizon
        : upcomingHorizon;
    if (!p.endsAt.isAfter(now) || p.startsAt.isAfter(now.add(horizon))) {
      continue;
    }
    if (!seen.add('${p.kind.json} ${p.dossierRef ?? subjectKey(p.label)}')) {
      continue;
    }
    final dossierUrl = switch (p.dossierRef) {
      final ref? => Dossier(uid: ref, title: '').url,
      null => null,
    };
    items.add(
      UpcomingItem(
        id: p.id,
        kind: p.kind,
        startsAt: p.startsAt,
        seanceRef: p.seanceRef,
        label: p.label,
        shortTitle: _shortTitle(p, dossierUrl, decisions, dossiers),
        inProgress: p.kind == UpcomingKind.discussion && p.followUp,
        dossierRef: p.dossierRef,
        dossierUrl: dossierUrl,
      ),
    );
  }
  return items;
}

String _shortTitle(
  AgendaPoint p,
  String? dossierUrl,
  List<DecisionSummary> decisions,
  DossierIndex? dossiers,
) {
  final label = cleanLabel(p.label);
  // L'index va de la décision la plus récente à la plus ancienne.
  final title =
      decisions
          .where((d) => dossierUrl != null && d.dossierUrl == dossierUrl)
          .firstOrNull
          ?.displayTitle ??
      (p.dossierRef == null ? null : dossiers?.dossier(p.dossierRef!)?.title);
  if (title == null || title.trim().isEmpty) return label;
  final precision = _trailingPrecision.firstMatch(label)?.group(0);
  return p.kind == UpcomingKind.voteSolennel &&
          precision != null &&
          !title.contains(precision)
      ? '${title.trim()} $precision'
      : title.trim();
}

final _trailingPrecision = RegExp(r'\([^()]*\)$');

/// Index des dossiers gardé par le job (`state/dossiers.json`), pour les
/// titres ; `null` s'il est absent ou illisible (on se passe de ces titres).
Future<DossierIndex?> _readDossiers(ObjectStore store) async {
  final raw = await store.read(dossiersStateKey);
  if (raw == null) return null;
  try {
    return DossierIndex.fromJson(
      (jsonDecode(raw) as Map<String, Object?>)['index'],
    );
  } on Object {
    return null;
  }
}

/// État de l'agenda (`state/agenda.json`) : `ETag` de la dernière archive
/// lue et points des séances pas encore finies à ce moment-là.
class AgendaState {
  AgendaState({
    required this.etag,
    required this.fetchedAt,
    this.points = const [],
  });

  final String? etag;
  final DateTime fetchedAt;
  final List<AgendaPoint> points;

  static const _version = 1;

  /// Lit l'état ; `null` s'il n'existe pas. Un état illisible est signalé
  /// dans [warnings] et vaut absence (l'agenda sera retéléchargé).
  static Future<AgendaState?> read(
    ObjectStore store,
    List<String> warnings,
  ) async {
    final raw = await store.read(agendaStateKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?> || json['version'] != _version) {
        throw const FormatException('version inattendue');
      }
      return AgendaState(
        etag: json['etag'] as String?,
        fetchedAt: DateTime.parse(json['fetchedAt'] as String),
        points: [
          for (final p in json['points'] as List) ?AgendaPoint.tryFromJson(p),
        ],
      );
    } on Object catch (e) {
      warnings.add("état de l'agenda illisible, il sera reconstruit ($e)");
      return null;
    }
  }

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'version': _version,
    'etag': ?etag,
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'points': [for (final p in points) p.toJson()],
  });

  Future<void> write(ObjectStore store) =>
      store.write(agendaStateKey, encode(), cacheControl: 'no-store');
}
