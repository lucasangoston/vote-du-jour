import 'dart:convert';

import 'package:vote_contract/vote_contract.dart';

import '../decision_details.dart';
import '../decision_selector.dart';
import '../dossier_index.dart';
import '../job.dart' show dossiersStateKey, indexCacheControl;
import '../object_store.dart';
import 'live_state.dart';
import 'paris_time.dart';
import 'reconciler.dart';
import 'site_reader.dart';
import 'site_source.dart';

/// Plages de la détection en direct, en heure de Paris : jours de la semaine
/// (1 = lundi) et heures [startHour, endHour[. Par défaut, du lundi au
/// vendredi de 9 h à minuit, à ajuster avec les mesures du spike #15.
class LiveWindow {
  const LiveWindow({
    this.days = const {1, 2, 3, 4, 5},
    this.startHour = 9,
    this.endHour = 24,
  });

  /// Lit `--live-days 1-5` (ou `1,2,3`) et `--live-hours 9-24`.
  factory LiveWindow.parse({required String days, required String hours}) {
    final h = _range(hours, 0, 24);
    if (h.first >= h.last) {
      throw FormatException('plage horaire vide : $hours');
    }
    final d = <int>{};
    for (final part in days.split(',')) {
      final r = _range(part, 1, 7);
      for (var i = r.first; i <= r.last; i++) {
        d.add(i);
      }
    }
    return LiveWindow(days: d, startHour: h.first, endHour: h.last);
  }

  final Set<int> days;
  final int startHour;
  final int endHour;

  /// L'instant [utc] est-il dans la plage, à Paris ?
  bool contains(DateTime utc) {
    final p = toParis(utc);
    return days.contains(p.weekday) && p.hour >= startHour && p.hour < endHour;
  }

  @override
  String toString() =>
      'jours ${(days.toList()..sort()).join(',')}, '
      '${startHour}h-${endHour}h (heure de Paris)';

  static List<int> _range(String s, int min, int max) {
    final parts = s.trim().split('-').map((p) => int.tryParse(p.trim()));
    final values = parts.toList();
    if (values.isEmpty ||
        values.length > 2 ||
        values.any((v) => v == null || v < min || v > max)) {
      throw FormatException('plage invalide : $s ($min-$max attendu)');
    }
    return [values.first!, values.last!];
  }
}

/// Issue d'un passage de la détection en direct.
sealed class LiveOutcome {
  const LiveOutcome({this.warnings = const []});

  /// Problèmes non bloquants, à journaliser.
  final List<String> warnings;

  String get _warnings => [for (final w in warnings) '\nAttention : $w'].join();
}

/// Hors des plages de séance : aucune requête.
class LiveOutsideWindow extends LiveOutcome {
  const LiveOutsideWindow(this.window);

  final LiveWindow window;

  @override
  String toString() => 'Hors plage de détection ($window) : rien à faire.';
}

/// Le passage n'a pas pu se faire (pas encore d'instantané du jeu de
/// données) : rien n'a été publié.
class LiveSkipped extends LiveOutcome {
  const LiveSkipped(this.reason, {super.warnings});

  final String reason;

  @override
  String toString() => 'Détection en direct ignorée : $reason.$_warnings';
}

/// Le site est illisible (panne, ou structure changée) : l'erreur est
/// journalisée, l'index publié et l'état restent tels quels.
class LiveFailed extends LiveOutcome {
  const LiveFailed(this.error, {super.warnings});

  final Object error;

  @override
  String toString() =>
      'Lecture du site de l\'Assemblée impossible, index inchangé : '
      '$error$_warnings';
}

/// Le site a été lu.
class LiveChecked extends LiveOutcome {
  const LiveChecked({
    required this.listed,
    required this.confirmedUpTo,
    required this.newSinceDump,
    required this.detected,
    required this.provisional,
    required this.published,
    super.warnings,
  });

  /// Scrutins lus sur la page de liste.
  final List<SiteScrutin> listed;

  /// Dernier numéro du jeu de données.
  final int confirmedUpTo;

  /// Scrutins de la liste absents du jeu de données.
  final int newSinceDump;

  /// Scrutins provisoires détectés à ce passage.
  final List<SiteScrutin> detected;

  /// Décisions provisoires de l'index publié.
  final List<DecisionSummary> provisional;

  /// L'index a-t-il été réécrit ?
  final bool published;

  @override
  String toString() {
    final numeros = listed.map((s) => s.numero);
    return [
          '${listed.length} scrutins lus sur le site '
              '(n° ${numeros.reduce((a, b) => a < b ? a : b)} à '
              '${numeros.reduce((a, b) => a > b ? a : b)}), '
              '$newSinceDump après le jeu de données (n° $confirmedUpTo).',
          '${detected.length} nouveaux scrutins provisoires retenus'
              '${detected.isEmpty ? '.' : ' :'}',
          for (final s in detected)
            '  ${s.numero} ${s.result?.json} ${s.titre}',
          '${provisional.length} décisions provisoires dans l\'index'
              '${provisional.isEmpty ? '.' : ' :'}',
          for (final d in provisional)
            '  ${d.numero} ${formatDate(d.date)} ${d.result.json} '
                '${d.displayTitle} (${d.stage})',
          published ? 'Index republié ($indexPath).' : 'Index inchangé.',
        ].join('\n') +
        _warnings;
  }
}

/// Nombre maximal de pages de scrutin lues par passage, quand la liste ne
/// donne pas le sort d'un scrutin susceptible d'être une décision.
const maxScrutinPagesPerPass = 5;

/// Un passage de la détection en direct : un GET de la liste des scrutins du
/// site, plus un GET par nouveau scrutin dont la liste ne donne pas le sort.
///
/// Les scrutins absents du jeu de données (numéro supérieur au dernier de
/// l'instantané) passent par le sélecteur ; ceux qu'il retient deviennent des
/// scrutins provisoires, gardés dans l'état ([liveStateKey]) jusqu'à leur
/// confirmation. L'index est reconstruit par [reconcile] à partir de
/// l'instantané du jeu de données ([confirmedSnapshotKey]) et n'est réécrit
/// que si ses décisions changent.
///
/// Une erreur de lecture du site renvoie [LiveFailed] sans rien écrire.
Future<LiveOutcome> runLivePass({
  required SiteSource site,
  required ObjectStore store,
  DateTime Function() clock = DateTime.now,
  int maxScrutinPages = maxScrutinPagesPerPass,
}) async {
  final warnings = <String>[];
  final now = clock().toUtc();

  final snapshot = await ConfirmedSnapshot.read(store, warnings);
  if (snapshot == null) {
    return LiveSkipped(
      "pas encore d'instantané du jeu de données ($confirmedSnapshotKey), "
      'écrit par la prochaine publication du jeu de données',
      warnings: warnings,
    );
  }
  final state = await LiveState.read(store, warnings);

  final List<SiteScrutin> listed;
  try {
    listed = parseScrutinList(await site.fetchList());
  } on Object catch (e) {
    return LiveFailed(e, warnings: warnings);
  }

  final upTo = snapshot.lastNumero;
  final reference = [upTo, ?state.lastSeenNumero].reduce(_max);
  final oldest = listed.map((s) => s.numero).reduce(_min);
  final newest = listed.map((s) => s.numero).reduce(_max);
  if (oldest > reference + 1) {
    warnings.add(
      'scrutins ${reference + 1} à ${oldest - 1} absents de la liste du site '
      '(trop de scrutins depuis le passage précédent) : ils seront publiés '
      'avec le jeu de données',
    );
  }

  final known = {for (final p in state.provisional) p.uid: p};
  final detected = <SiteScrutin>[];
  var pages = 0;
  for (final listedScrutin in listed.reversed) {
    if (listedScrutin.numero <= upTo) continue;
    if (known[listedScrutin.uid] case final previous?) {
      // Déjà connu : la liste fait foi, la page lue avant complète.
      known[previous.uid] = ProvisionalScrutin(
        site: listedScrutin.completedWith(previous.site),
        detectedAt: previous.detectedAt,
      );
      continue;
    }
    if (!_mayBeDecision(listedScrutin)) continue;
    var s = listedScrutin;
    if (s.result == null) {
      if (pages >= maxScrutinPages) {
        warnings.add(
          'scrutin ${s.numero} : sort inconnu, relu au passage suivant',
        );
        continue;
      }
      pages++;
      try {
        s = s.completedWith(
          parseScrutinPage(await site.fetchScrutin(s.numero), numero: s.numero),
        );
      } on Object catch (e) {
        warnings.add('page du scrutin ${s.numero} illisible ($e)');
        continue;
      }
      if (s.result == null) {
        warnings.add(
          'scrutin ${s.numero} : sort introuvable, ignoré pour le moment',
        );
        continue;
      }
    }
    if (!_isDecision(s, s.result!)) continue;
    detected.add(s);
    known[s.uid] = ProvisionalScrutin(site: s, detectedAt: now);
  }

  final dossiers = await _readDossierIndex(store, warnings);
  final reconciled = reconcile(
    confirmed: snapshot.scrutins,
    confirmedUpTo: upTo,
    provisional: [for (final p in known.values) p.toScrutin()],
    generatedAt: now,
    dossiers: dossiers,
  );

  // Détails des décisions provisoires avant l'index qui renvoie vers eux
  // (#6) ; seuls ceux qui ont changé sont réécrits.
  await publishDecisionDetails(
    store,
    buildProvisionalDetails(reconciled.pending, reconciled.index),
  );

  final changed = !_sameDecisions(
    await store.read(indexPath),
    reconciled.index,
  );
  if (changed) {
    await store.write(
      indexPath,
      const JsonEncoder.withIndent('  ').convert(reconciled.index.toJson()),
      cacheControl: indexCacheControl,
    );
  }
  final pendingUids = {for (final s in reconciled.pending) s.uid};
  await LiveState(
    lastSeenNumero: _max(reference, newest),
    checkedAt: now,
    provisional: [
      for (final p
          in known.values.toList()
            ..sort((a, b) => a.numero.compareTo(b.numero)))
        if (pendingUids.contains(p.uid)) p,
    ],
  ).write(store);

  return LiveChecked(
    listed: listed,
    confirmedUpTo: upTo,
    newSinceDump: listed.where((s) => s.numero > upTo).length,
    detected: detected,
    provisional: [
      for (final d in reconciled.index.decisions)
        if (d.status == DecisionStatus.provisoire) d,
    ],
    published: changed,
    warnings: warnings,
  );
}

/// Le scrutin peut-il être une décision, quel que soit son sort (inconnu) ?
/// Évite de lire la page des amendements et des articles.
bool _mayBeDecision(SiteScrutin s) => switch (s.result) {
  final result? => _isDecision(s, result),
  null => VoteResult.values.any((r) => _isDecision(s, r)),
};

/// Mêmes règles que l'index : retenu par le sélecteur, ou vote sur l'article
/// unique d'un texte (qui vaut vote sur l'ensemble).
bool _isDecision(SiteScrutin s, VoteResult result) =>
    classifyScrutin(titre: s.titre, codeTypeVote: null, sort: result)
        is Retained ||
    isArticleUniqueVote(s.titre);

/// Les décisions de l'index publié [published] (JSON) sont-elles celles de
/// [index] ? La date de génération n'est pas comparée.
bool _sameDecisions(String? published, DecisionIndex index) {
  if (published == null) return false;
  try {
    final json = jsonDecode(published);
    return json is Map &&
        jsonEncode(json['decisions']) ==
            jsonEncode(index.toJson()['decisions']);
  } on FormatException {
    return false;
  }
}

/// Index des dossiers gardé par le job ([dossiersStateKey]), ou `null`.
Future<DossierIndex?> _readDossierIndex(
  ObjectStore store,
  List<String> warnings,
) async {
  try {
    final raw = await store.read(dossiersStateKey);
    if (raw == null) return null;
    return DossierIndex.fromJson((jsonDecode(raw) as Map)['index']);
  } on Object catch (e) {
    warnings.add(
      'index des dossiers illisible, libellés tirés des intitulés ($e)',
    );
    return null;
  }
}

int _max(int a, int b) => a > b ? a : b;
int _min(int a, int b) => a < b ? a : b;
