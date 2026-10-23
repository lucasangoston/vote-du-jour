import 'dart:convert';

import 'package:vote_contract/vote_contract.dart';

import '../agenda/agenda_pass.dart' show AgendaState;
import '../agenda/in_debate.dart';
import '../decision_details.dart';
import '../decision_selector.dart';
import '../dossier_index.dart';
import '../job.dart' show dossiersStateKey, indexCacheControl;
import '../object_store.dart';
import '../summary/summary_cache.dart';
import 'live_state.dart';
import 'paris_time.dart';
import 'reconciler.dart';
import 'site_reader.dart';
import 'site_source.dart';

/// Plages de la détection en direct, en heure de Paris : jours de la semaine
/// (1 = lundi) et heures [startHour, endHour[. Par défaut, du lundi au
/// vendredi de 9 h à minuit (plages confirmées par le spike #15).
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
    this.listPages = 1,
    required this.confirmedUpTo,
    required this.newSinceDump,
    required this.detected,
    required this.provisional,
    required this.published,
    this.inDebate,
    super.warnings,
  });

  /// Scrutins lus sur les pages de liste, du plus récent au plus ancien.
  final List<SiteScrutin> listed;

  /// Nombre de pages de liste lues.
  final int listPages;

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

  /// Texte en débat de l'index (#55).
  final InDebate? inDebate;

  @override
  String toString() {
    final numeros = listed.map((s) => s.numero);
    return [
          '${listed.length} scrutins lus sur le site '
              '($listPages page${listPages > 1 ? 's' : ''} de liste, n°${numeros.reduce((a, b) => a < b ? a : b)} à '
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
          if (inDebate case final d?)
            'En débat : ${d.shortTitle}, ${d.articles.length} articles.',
          published ? 'Index republié ($indexPath).' : 'Index inchangé.',
        ].join('\n') +
        _warnings;
  }
}

/// Nombre maximal de pages de scrutin lues par passage, quand la liste ne
/// donne pas le sort d'un scrutin susceptible d'être une décision.
const maxScrutinPagesPerPass = 5;

/// Nombre maximal de pages de la liste des scrutins (50 par page) lues par
/// passage : 200 scrutins, bien plus que ce qu'une séance de budget vote en
/// dix minutes (33 vus entre deux passages espacés de plusieurs heures).
const maxListPagesPerPass = 4;

/// Pause entre deux pages de la liste. Le robots.txt du site demande
/// `Crawl-delay: 30` : on le respecte à la lettre. La pause ne coûte que
/// lors des rares passages qui lisent plus d'une page (au plus 1 min 30 pour
/// 4 pages, dans les 8 minutes du job).
const listPageDelay = Duration(seconds: 30);

/// Un passage de la détection en direct : un GET de la liste des scrutins du
/// site, plus un GET par nouveau scrutin dont la liste ne donne pas le sort.
///
/// Pagination : tant que la page lue ne contient que des scrutins jamais vus
/// (le plus ancien est au-delà du suivant du dernier scrutin connu : dernier
/// numéro de l'état, [LiveState.lastSeenNumero], ou du jeu de données), la
/// page suivante est lue, après une pause de [pageDelay], jusqu'à
/// [maxListPages] pages. Au-delà, les scrutins manquants sont signalés et
/// seront publiés avec le jeu de données. L'erreur de lecture d'une page
/// suivante n'est qu'un avertissement : le passage continue avec les pages
/// lues, et l'état garde le dernier numéro connu pour relire le trou au
/// passage suivant.
///
/// Les scrutins absents du jeu de données (numéro supérieur au dernier de
/// l'instantané) passent par le sélecteur ; ceux qu'il retient deviennent des
/// scrutins provisoires, gardés dans l'état ([liveStateKey]) jusqu'à leur
/// confirmation. L'index est reconstruit par [reconcile] à partir de
/// l'instantané du jeu de données ([confirmedSnapshotKey]).
///
/// Le bloc « En débat » (#55) est recalculé ([buildInDebate]) avec l'ordre
/// du jour gardé par le passage de l'agenda ([AgendaState]), les votes sur
/// les articles du jeu de données ([ArticleVotesState]) et ceux de la liste
/// du site plus récents ; sans agenda connu, le bloc publié est gardé.
/// L'index n'est réécrit que si ses décisions ou ce bloc changent.
///
/// Une erreur de lecture du site renvoie [LiveFailed] sans rien écrire.
Future<LiveOutcome> runLivePass({
  required SiteSource site,
  required ObjectStore store,
  DateTime Function() clock = DateTime.now,
  int maxScrutinPages = maxScrutinPagesPerPass,
  int maxListPages = maxListPagesPerPass,
  Duration pageDelay = listPageDelay,
  Future<void> Function(Duration)? sleep,
}) async {
  final pause = sleep ?? (d) => Future<void>.delayed(d);
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

  final upTo = snapshot.lastNumero;
  final reference = [upTo, ?state.lastSeenNumero].reduce(_max);

  // Pages de la liste, du plus récent au plus ancien ; un scrutin voté entre
  // deux lectures décale la liste : les doublons sont écartés.
  final listed = <SiteScrutin>[];
  final listedNumeros = <int>{};
  var listPages = 0;
  var readFailed = false;
  while (true) {
    final List<SiteScrutin> page;
    try {
      if (listPages > 0) await pause(pageDelay);
      page = parseScrutinList(await site.fetchList(page: listPages + 1));
    } on Object catch (e) {
      if (listPages == 0) return LiveFailed(e, warnings: warnings);
      warnings.add(
        'page ${listPages + 1} de la liste illisible, relue au passage '
        'suivant ($e)',
      );
      readFailed = true;
      break;
    }
    listPages++;
    for (final s in page) {
      if (listedNumeros.add(s.numero)) listed.add(s);
    }
    final pageOldest = page.map((s) => s.numero).reduce(_min);
    if (pageOldest <= reference + 1 || listPages >= maxListPages) break;
  }

  final oldest = listed.map((s) => s.numero).reduce(_min);
  final newest = listed.map((s) => s.numero).reduce(_max);
  if (oldest > reference + 1 && !readFailed) {
    warnings.add(
      'scrutins ${reference + 1} à ${oldest - 1} absents des $listPages '
      'pages lues de la liste du site (trop de scrutins depuis le passage '
      'précédent) : ils seront publiés avec le jeu de données',
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
    // Arcs calculés par le job avec le vote par groupe (#67).
    arcs: snapshot.arcs,
  );
  // Les résumés (#9) sont rédigés par le job horaire, pas ici : le passage
  // en direct applique seulement ceux du cache, et ceux de l'index publié
  // si le cache est perdu. Il n'écrit jamais le cache.
  final published = await store.read(indexPath);
  final publishedIndex = _tryIndex(published);
  final summaries = await SummaryCache.read(store, warnings)
    ..adoptPublished(publishedIndex, now: now);
  // L'ordre du jour (#52) n'est mis à jour que par le job horaire : le
  // passage en direct garde celui de l'index publié.
  final summarized = summaries.applyTo(reconciled.index);
  final agenda = await AgendaState.read(store, warnings);
  final articleVotes = await ArticleVotesState.read(store, warnings);
  final inDebate = agenda == null
      ? publishedIndex?.inDebate
      : buildInDebate(
          agenda.points,
          now: now,
          votes: articleVotes?.votes ?? const [],
          confirmedUpTo: articleVotes?.lastNumero ?? upTo,
          provisional: [
            for (final s in listed)
              if (s.result != null)
                ?ArticleVote.fromScrutin(
                  s.toScrutin(fallbackDate: parisDay(now)),
                ),
          ],
          previous: publishedIndex?.inDebate,
          decisions: summarized.decisions,
          dossiers: dossiers,
        );
  final index = summarized
      .withUpcoming(publishedIndex?.upcoming)
      .withInDebate(inDebate);

  // Détails des décisions provisoires avant l'index qui renvoie vers eux
  // (#6) ; seuls ceux qui ont changé sont réécrits.
  await publishDecisionDetails(
    store,
    buildProvisionalDetails(reconciled.pending, index),
  );

  final changed = !_samePublished(published, index);
  if (changed) {
    await store.write(
      indexPath,
      const JsonEncoder.withIndent('  ').convert(index.toJson()),
      cacheControl: indexCacheControl,
    );
  }
  final pendingUids = {for (final s in reconciled.pending) s.uid};
  await LiveState(
    // Page suivante illisible : le dernier numéro connu ne bouge pas, pour
    // relire le trou au passage suivant.
    lastSeenNumero: readFailed ? reference : _max(reference, newest),
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
    listPages: listPages,
    confirmedUpTo: upTo,
    newSinceDump: listed.where((s) => s.numero > upTo).length,
    detected: detected,
    provisional: [
      for (final d in index.decisions)
        if (d.status == DecisionStatus.provisoire) d,
    ],
    published: changed,
    inDebate: inDebate,
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

/// Les décisions et le texte en débat de l'index publié [published] (JSON)
/// sont-ils ceux de [index] ? La date de génération n'est pas comparée.
bool _samePublished(String? published, DecisionIndex index) {
  if (published == null) return false;
  try {
    final json = jsonDecode(published);
    final next = index.toJson();
    return json is Map &&
        jsonEncode(json['decisions']) == jsonEncode(next['decisions']) &&
        jsonEncode(json['inDebate']) == jsonEncode(next['inDebate']);
  } on FormatException {
    return false;
  }
}

DecisionIndex? _tryIndex(String? raw) {
  if (raw == null) return null;
  try {
    return DecisionIndex.fromJson(jsonDecode(raw));
  } on Object {
    return null;
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
