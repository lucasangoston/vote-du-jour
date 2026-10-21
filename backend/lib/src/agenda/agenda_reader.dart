import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:vote_contract/vote_contract.dart';

import '../decision_selector.dart' show normalizeTitle;

/// Organe des séances publiques de l'Assemblée nationale dans l'agenda.
const assembleeSeanceOrgane = 'PO838901';

/// Durée supposée d'une séance dont l'agenda ne donne pas la fin
/// (`timeStampFin` est presque toujours absent avant la séance).
const defaultSeanceDuration = Duration(hours: 6);

/// Un point de l'ordre du jour d'une séance publique de l'Assemblée, retenu
/// pour le bloc « À venir » : discussion d'un texte (ou suite de sa
/// discussion), vote solennel ou vote par scrutin public.
///
/// Le passage de l'agenda garde ces points dans son état
/// (`state/agenda.json`) : quand l'agenda n'a pas changé, le bloc est
/// recalculé sans le retélécharger.
class AgendaPoint {
  const AgendaPoint({
    required this.id,
    required this.seanceRef,
    required this.startsAt,
    required this.endsAt,
    required this.kind,
    required this.label,
    this.followUp = false,
    this.dossierRef,
  });

  /// Identifiant du point (`RUANR5L17S2027IDS30964PT53289`).
  final String id;

  /// Séance où il est inscrit (`RUANR5L17S2027IDS30964`).
  final String seanceRef;

  /// Début de la séance, en UTC.
  final DateTime startsAt;

  /// Fin de la séance (`timeStampFin`, sinon début +
  /// [defaultSeanceDuration]), en UTC : le point reste « à venir » jusque-là.
  final DateTime endsAt;

  final UpcomingKind kind;

  /// « Suite de la discussion » : la discussion du texte a commencé lors
  /// d'une séance précédente.
  final bool followUp;

  /// Libellé du point (`objet`), tel que publié.
  final String label;

  /// Dossier législatif : celui de l'ordre du jour, ou retrouvé par le
  /// libellé ([readAgendaArchive]).
  final String? dossierRef;

  static AgendaPoint? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    final seanceRef = json['seanceRef'];
    final startsAt = DateTime.tryParse('${json['startsAt']}');
    final endsAt = DateTime.tryParse('${json['endsAt']}');
    final kind = UpcomingKind.tryParse(json['kind']);
    final label = json['label'];
    final dossierRef = json['dossierRef'];
    if (id is! String ||
        seanceRef is! String ||
        startsAt == null ||
        endsAt == null ||
        kind == null ||
        label is! String) {
      return null;
    }
    return AgendaPoint(
      id: id,
      seanceRef: seanceRef,
      startsAt: startsAt.toUtc(),
      endsAt: endsAt.toUtc(),
      kind: kind,
      label: label,
      followUp: json['followUp'] == true,
      dossierRef: dossierRef is String ? dossierRef : null,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'seanceRef': seanceRef,
    'startsAt': startsAt.toUtc().toIso8601String(),
    'endsAt': endsAt.toUtc().toIso8601String(),
    'kind': kind.json,
    if (followUp) 'followUp': true,
    'label': label,
    'dossierRef': ?dossierRef,
  };

  @override
  String toString() =>
      'AgendaPoint($id ${kind.json}${followUp ? ' (suite)' : ''} '
      '${startsAt.toIso8601String()} $label ${dossierRef ?? '-'})';
}

/// Points de l'agenda retenus et fichiers ignorés.
typedef AgendaRead = ({List<AgendaPoint> points, int unreadable});

/// Lit l'archive `Agenda.json.zip` (une réunion par fichier,
/// `json/reunion/<uid>.json`) et renvoie, dans l'ordre chronologique puis
/// celui de l'ordre du jour, les points des séances de l'Assemblée qui ne
/// sont pas finies à l'instant [since] :
///
/// - séances publiques de l'Assemblée seulement (`@xsi:type` `seance_type`,
///   uid `RUAN…`, organe [assembleeSeanceOrgane]) : ni le Sénat (`RUSN…`) ni
///   les commissions ;
/// - séance et point à l'état « Confirmé » (un point reporté passe à
///   « Supprimé » et disparaît) ;
/// - points « Discussion », « Suite de la discussion », « Vote solennel » et
///   « Vote par scrutin public » ; une discussion sans dossier qui ne
///   discute pas un texte (« Débat sur les finances locales ») est écartée.
///
/// L'ordre du jour ne donne souvent pas le dossier d'un vote solennel
/// (`dossierRef` vide) : il est retrouvé par le texte nommé dans le libellé,
/// comparé à celui des autres points de l'Assemblée qui ont un dossier
/// (« Vote solennel sur le projet de loi de finances pour 2027 (première
/// partie) » ↔ « Suite de la discussion du projet de loi de finances pour
/// 2027 (première partie) »), seulement s'il désigne un seul dossier.
///
/// Un fichier illisible est ignoré et compté dans `unreadable` ; une archive
/// illisible lève une exception.
AgendaRead readAgendaArchive(List<int> zipBytes, {required DateTime since}) {
  final archive = ZipDecoder().decodeBytes(zipBytes);
  var unreadable = 0;
  final seances = <_Seance>[];
  // Texte nommé par un libellé → dossiers des points qui le nomment.
  final dossiersBySubject = <String, Set<String>>{};
  for (final file in archive) {
    final name = file.name.split('/').last;
    if (!file.isFile || !name.startsWith('RUAN') || !name.endsWith('.json')) {
      continue;
    }
    final _Seance? seance;
    try {
      seance = _readSeance(jsonDecode(utf8.decode(file.content)));
    } on Object {
      unreadable++;
      continue;
    }
    if (seance == null) continue;
    for (final p in seance.points) {
      if (p.dossierRef case final dossier?) {
        (dossiersBySubject[subjectKey(p.label)] ??= {}).add(dossier);
      }
    }
    if (seance.confirmed && seance.endsAt.isAfter(since)) seances.add(seance);
  }
  seances.sort((a, b) {
    final byStart = a.startsAt.compareTo(b.startsAt);
    return byStart != 0 ? byStart : a.uid.compareTo(b.uid);
  });

  final points = <AgendaPoint>[];
  for (final seance in seances) {
    for (final p in seance.points) {
      if (!p.confirmed) continue;
      final kind = _kinds[p.type];
      if (kind == null) continue;
      final dossierRef =
          p.dossierRef ??
          switch (dossiersBySubject[subjectKey(p.label)]) {
            final dossiers? when dossiers.length == 1 => dossiers.single,
            _ => null,
          };
      if (kind.$1 == UpcomingKind.discussion &&
          dossierRef == null &&
          !_discussesText.hasMatch(normalizeTitle(p.label))) {
        continue;
      }
      points.add(
        AgendaPoint(
          id: p.uid,
          seanceRef: seance.uid,
          startsAt: seance.startsAt,
          endsAt: seance.endsAt,
          kind: kind.$1,
          followUp: kind.$2,
          label: p.label,
          dossierRef: dossierRef,
        ),
      );
    }
  }
  return (points: points, unreadable: unreadable);
}

/// `typePointODJ` retenus : nature du point et « suite de la discussion ».
const _kinds = {
  'Discussion': (UpcomingKind.discussion, false),
  'Suite de la discussion': (UpcomingKind.discussion, true),
  'Vote solennel': (UpcomingKind.voteSolennel, false),
  'Vote par scrutin public': (UpcomingKind.voteSolennel, false),
};

final _discussesText = RegExp(r'^(?:suite de la )?discussion\b');

/// Formule de procédure en tête d'un libellé de l'ordre du jour, jusqu'au
/// texte nommé (« Vote solennel sur le », « Suite de la discussion de la »).
final _procedurePrefix = RegExp(
  r'^(?:suite de la discussion|discussion|vote solennel|'
  r'vote par scrutin public|explications de vote(?: et vote)?'
  r"(?: par scrutin public)?)\s+(?:sur |du |des |de |d[‘’ʼ'])?"
  r"(?:la |le |les |l[‘’ʼ'])?",
  caseSensitive: false,
);

/// Texte nommé par un libellé de l'ordre du jour, normalisé pour comparer
/// deux libellés : « projet de loi de finances pour 2027 (première
/// partie) ».
String subjectKey(String label) => normalizeTitle(label)
    .replaceFirst(_procedurePrefix, '')
    .replaceAll('œ', 'oe')
    .replaceFirst(RegExp(r'[\s.]+$'), '');

/// Libellé [label] sans sa formule de procédure, avec une majuscule
/// initiale : « Projet de loi de finances pour 2027 (première partie) ».
String cleanLabel(String label) {
  final s = label.replaceAll(RegExp(r'\s+'), ' ').trim();
  final rest = s
      .replaceFirst(_procedurePrefix, '')
      .replaceFirst(RegExp(r'[\s.]+$'), '');
  if (rest.isEmpty) return s;
  return rest[0].toUpperCase() + rest.substring(1);
}

class _Seance {
  _Seance({
    required this.uid,
    required this.startsAt,
    required this.endsAt,
    required this.confirmed,
    required this.points,
  });

  final String uid;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool confirmed;
  final List<_Point> points;
}

class _Point {
  _Point({
    required this.uid,
    required this.type,
    required this.label,
    required this.confirmed,
    this.dossierRef,
  });

  final String uid;
  final String? type;
  final String label;
  final bool confirmed;
  final String? dossierRef;
}

const _confirmed = 'Confirmé';

/// Séance publique de l'Assemblée décrite par [json], ou `null` pour une
/// autre réunion. Lève une exception si le fichier n'a pas le format
/// attendu.
_Seance? _readSeance(Object? json) {
  final r = (json as Map<String, Object?>)['reunion'] as Map<String, Object?>;
  final uid = r['uid'] as String;
  if (r['@xsi:type'] != 'seance_type' ||
      !uid.startsWith('RUAN') ||
      r['organeReuniRef'] != assembleeSeanceOrgane) {
    return null;
  }
  final startsAt = DateTime.parse(r['timeStampDebut'] as String).toUtc();
  final end = r['timeStampFin'];
  final endsAt = end is String
      ? DateTime.parse(end).toUtc()
      : startsAt.add(defaultSeanceDuration);
  final odj = r['ODJ'];
  final pointsODJ = odj is Map<String, Object?> ? odj['pointsODJ'] : null;
  final raw = pointsODJ is Map<String, Object?> ? pointsODJ['pointODJ'] : null;
  return _Seance(
    uid: uid,
    startsAt: startsAt,
    endsAt: endsAt,
    confirmed: _etat(r) == _confirmed,
    points: [
      // Conversion XML → JSON : un point unique est un objet, pas une liste.
      for (final p in switch (raw) {
        final List<Object?> l => l,
        final Map<String, Object?> m => [m],
        _ => const <Object?>[],
      })
        if (p is Map<String, Object?> &&
            p['uid'] is String &&
            p['objet'] is String)
          _Point(
            uid: p['uid'] as String,
            type: p['typePointODJ'] as String?,
            label: (p['objet'] as String).trim(),
            confirmed: _etat(p) == _confirmed,
            dossierRef: _dossierRef(p['dossiersLegislatifsRefs']),
          ),
    ],
  );
}

String? _etat(Map<String, Object?> m) => switch (m['cycleDeVie']) {
  {'etat': final String etat} => etat,
  _ => null,
};

/// Premier dossier cité (`dossierRef` est un texte, ou une liste quand le
/// point en cite plusieurs).
String? _dossierRef(Object? refs) => switch (refs) {
  {'dossierRef': final String ref} => ref,
  {'dossierRef': final List<Object?> refs} =>
    refs.whereType<String>().firstOrNull,
  _ => null,
};
