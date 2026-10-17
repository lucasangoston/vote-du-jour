import 'dart:convert';

import 'package:vote_contract/vote_contract.dart';

import '../decision_selector.dart';
import '../object_store.dart';
import '../scrutin.dart';
import 'paris_time.dart';
import 'site_reader.dart';

/// État de la détection en direct dans le bucket : les scrutins provisoires
/// connus, en attente du jeu de données.
const liveStateKey = 'state/live.json';

/// Scrutins du dernier jeu de données utiles à l'index, pour que la
/// détection en direct reconstruise l'index sans retélécharger l'archive
/// (27 Mo) toutes les dix minutes.
const confirmedSnapshotKey = 'state/scrutins-confirmes.json';

/// Scrutin provisoire : lu sur le site, pas encore dans le jeu de données.
class ProvisionalScrutin {
  const ProvisionalScrutin({required this.site, required this.detectedAt});

  final SiteScrutin site;

  /// Premier passage où il a été vu.
  final DateTime detectedAt;

  String get uid => site.uid;
  int get numero => site.numero;

  /// Le scrutin au format du jeu de données ; sans séance lisible, il est
  /// daté du jour (heure de Paris) de sa détection.
  Scrutin toScrutin() => site.toScrutin(fallbackDate: parisDay(detectedAt));

  Map<String, Object?> toJson() => {
    ...site.toJson(),
    'detectedAt': detectedAt.toUtc().toIso8601String(),
  };

  static ProvisionalScrutin fromJson(Object? json) {
    final detectedAt = json is Map<String, Object?>
        ? DateTime.tryParse('${json['detectedAt']}')
        : null;
    if (detectedAt == null) {
      throw const FormatException('Scrutin provisoire : detectedAt manquant');
    }
    return ProvisionalScrutin(
      site: SiteScrutin.fromJson(json),
      detectedAt: detectedAt,
    );
  }
}

/// Contenu de [liveStateKey].
class LiveState {
  const LiveState({
    this.lastSeenNumero,
    this.checkedAt,
    this.provisional = const [],
  });

  /// Plus grand numéro lu sur le site, pour repérer les scrutins manqués
  /// entre deux passages.
  final int? lastSeenNumero;

  /// Dernier passage réussi sur le site.
  final DateTime? checkedAt;

  /// Scrutins provisoires retenus par le sélecteur (ou portant sur l'article
  /// unique d'un texte), du plus ancien au plus récent.
  final List<ProvisionalScrutin> provisional;

  List<Scrutin> get provisionalScrutins => [
    for (final p in provisional) p.toScrutin(),
  ];

  /// Le même état, sans les scrutins provisoires absents de [uids] (ceux que
  /// le jeu de données a confirmés).
  LiveState keepOnly(Set<String> uids) => LiveState(
    lastSeenNumero: lastSeenNumero,
    checkedAt: checkedAt,
    provisional: [
      for (final p in provisional)
        if (uids.contains(p.uid)) p,
    ],
  );

  static const _version = 1;

  Map<String, Object?> toJson() => {
    'version': _version,
    'lastSeenNumero': ?lastSeenNumero,
    'checkedAt': ?checkedAt?.toUtc().toIso8601String(),
    'provisional': [for (final p in provisional) p.toJson()],
  };

  static LiveState fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['version'] != _version ||
        json['provisional'] is! List) {
      throw const FormatException('État de la détection : format inattendu');
    }
    return LiveState(
      lastSeenNumero: json['lastSeenNumero'] is int
          ? json['lastSeenNumero'] as int
          : null,
      checkedAt: DateTime.tryParse('${json['checkedAt']}'),
      provisional: [
        for (final p in json['provisional'] as List)
          ProvisionalScrutin.fromJson(p),
      ],
    );
  }

  /// Lit l'état ; un état absent ou illisible vaut un état vide (avec un
  /// avertissement dans [warnings]) : il ne doit jamais bloquer la
  /// publication.
  static Future<LiveState> read(
    ObjectStore store,
    List<String> warnings,
  ) async {
    try {
      final raw = await store.read(liveStateKey);
      return raw == null ? const LiveState() : fromJson(jsonDecode(raw));
    } on Object catch (e) {
      warnings.add('état de la détection en direct illisible, ignoré ($e)');
      return const LiveState();
    }
  }

  Future<void> write(ObjectStore store) => store.write(
    liveStateKey,
    const JsonEncoder.withIndent('  ').convert(toJson()),
    cacheControl: 'no-store',
  );
}

/// Contenu de [confirmedSnapshotKey] : les scrutins du dernier jeu de données
/// qu'utilise [buildDecisionIndex] (retenus, ou sur l'article unique d'un
/// texte), sans le vote par groupe.
class ConfirmedSnapshot {
  const ConfirmedSnapshot({
    required this.lastNumero,
    required this.scrutins,
    this.lastModified,
  });

  /// Garde de [all] (tout le jeu de données) les scrutins utiles à l'index.
  factory ConfirmedSnapshot.fromDump(
    Iterable<Scrutin> all, {
    String? lastModified,
  }) {
    var lastNumero = 0;
    final kept = <Scrutin>[];
    for (final s in all) {
      if (s.numero > lastNumero) lastNumero = s.numero;
      final c = classifyScrutin(
        titre: s.titre,
        codeTypeVote: s.codeTypeVote,
        sort: s.result,
      );
      if (c is Retained || isArticleUniqueVote(s.titre)) kept.add(s);
    }
    return ConfirmedSnapshot(
      lastNumero: lastNumero,
      scrutins: kept,
      lastModified: lastModified,
    );
  }

  /// Plus grand numéro du jeu de données : il est complet jusque-là.
  final int lastNumero;

  final List<Scrutin> scrutins;

  /// `Last-Modified` du jeu de données.
  final String? lastModified;

  static const _version = 1;

  Map<String, Object?> toJson() => {
    'version': _version,
    'lastModified': ?lastModified,
    'lastNumero': lastNumero,
    'scrutins': [for (final s in scrutins) _scrutinToJson(s)],
  };

  static ConfirmedSnapshot fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['version'] != _version ||
        json['lastNumero'] is! int ||
        json['scrutins'] is! List) {
      throw const FormatException('Instantané des scrutins : format inattendu');
    }
    return ConfirmedSnapshot(
      lastNumero: json['lastNumero'] as int,
      lastModified: json['lastModified'] is String
          ? json['lastModified'] as String
          : null,
      scrutins: [for (final s in json['scrutins'] as List) _scrutinFromJson(s)],
    );
  }

  /// Lit l'instantané, ou `null` s'il est absent ou illisible (avertissement
  /// dans [warnings]).
  static Future<ConfirmedSnapshot?> read(
    ObjectStore store,
    List<String> warnings,
  ) async {
    try {
      final raw = await store.read(confirmedSnapshotKey);
      return raw == null ? null : fromJson(jsonDecode(raw));
    } on Object catch (e) {
      warnings.add('instantané des scrutins illisible ($e)');
      return null;
    }
  }

  Future<void> write(ObjectStore store) => store.write(
    confirmedSnapshotKey,
    jsonEncode(toJson()),
    cacheControl: 'no-store',
  );
}

Map<String, Object?> _scrutinToJson(Scrutin s) => {
  'uid': s.uid,
  'numero': s.numero,
  'date': formatDate(s.date),
  'titre': s.titre,
  'codeTypeVote': s.codeTypeVote,
  'libelleTypeVote': s.libelleTypeVote,
  'result': s.result.json,
  'decompte': [
    s.decompte.pour,
    s.decompte.contre,
    s.decompte.abstentions,
    s.decompte.nonVotants,
  ],
  'dossierRef': ?s.dossierRef,
};

Scrutin _scrutinFromJson(Object? json) {
  if (json is! Map<String, Object?>) {
    throw const FormatException('Instantané : scrutin attendu');
  }
  final result = VoteResult.tryParse(json['result']);
  final date = DateTime.tryParse('${json['date']}T00:00:00Z');
  final decompte = json['decompte'];
  if (json['uid'] is! String ||
      json['numero'] is! int ||
      json['titre'] is! String ||
      json['codeTypeVote'] is! String ||
      result == null ||
      date == null ||
      decompte is! List ||
      decompte.length != 4 ||
      decompte.any((n) => n is! int)) {
    throw const FormatException('Instantané : scrutin malformé');
  }
  final counts = decompte.cast<int>();
  return Scrutin(
    uid: json['uid'] as String,
    numero: json['numero'] as int,
    date: date,
    titre: json['titre'] as String,
    codeTypeVote: json['codeTypeVote'] as String,
    libelleTypeVote: json['libelleTypeVote'] is String
        ? json['libelleTypeVote'] as String
        : '',
    result: result,
    decompte: Decompte(
      pour: counts[0],
      contre: counts[1],
      abstentions: counts[2],
      nonVotants: counts[3],
    ),
    dossierRef: json['dossierRef'] is String
        ? json['dossierRef'] as String
        : null,
    groupVotes: const [],
  );
}
