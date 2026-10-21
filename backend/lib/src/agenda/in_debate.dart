import 'dart:convert';

import 'package:vote_contract/vote_contract.dart';

import '../dossier_index.dart';
import '../live/paris_time.dart';
import '../object_store.dart';
import '../scrutin.dart';
import 'agenda_pass.dart' show pointShortTitle;
import 'agenda_reader.dart';

/// Un texte est « en débat » si sa discussion était inscrite à une séance
/// commencée dans les 7 derniers jours.
const inDebateWindow = Duration(days: 7);

/// Clé de l'état des votes sur les articles dans le bucket : les votes du
/// dernier jeu de données des scrutins utiles au bloc « En débat ».
const articleVotesKey = 'state/articles.json';

/// Les votes plus anciens ne sont pas gardés dans l'état.
const articleVotesRetention = Duration(days: 30);

/// Article visé par un scrutin et son sort pour le bloc « En débat », lus
/// sur l'intitulé [titre] du scrutin de sort [result] :
///
/// - « l'article 4 du projet de loi… », « l'article 40 (examen prioritaire)
///   du… », « l'article liminaire… », « l'article 3 bis A… » : article
///   adopté ou rejeté ;
/// - amendement de suppression d'un article adopté (« l'amendement n° 30 …
///   de suppression de l'article 5 du… », « l'amendement de suppression
///   n° 789 … à l'article 2 du… ») : article supprimé ;
/// - tout le reste est `null` : autres amendements, sous-amendements,
///   amendement de suppression rejeté (l'article est voté ensuite), article
///   unique (son vote vaut vote sur l'ensemble, publié comme décision).
///
/// Le jeu de données ne distingue pas les articles des amendements :
/// seul le début de l'intitulé le dit (voir `decision_selector.dart`).
({String number, ArticleOutcome outcome})? articleVoteOf(
  String titre,
  VoteResult result,
) {
  var t = titre
      .replaceAll(RegExp('[‘’ʼ`]'), "'")
      .replaceAll(RegExp(r'[\s  ]+'), ' ')
      .trim();
  if (t.startsWith('sur ')) t = t.substring(4);
  if (_articleTitle.firstMatch(t) case final m?) {
    if (m.group(1) == 'unique') return null;
    return (
      number: _numberOf(m),
      outcome: result == VoteResult.adopte
          ? ArticleOutcome.adopte
          : ArticleOutcome.rejete,
    );
  }
  if (!_amendementTitle.hasMatch(t) || result != VoteResult.adopte) {
    return null;
  }
  final m =
      _suppressionOf.firstMatch(t) ??
      (_suppressionAmendement.hasMatch(t) ? _atArticle.firstMatch(t) : null);
  if (m == null || m.group(1) == 'unique') return null;
  return (number: _numberOf(m), outcome: ArticleOutcome.supprime);
}

/// Numéro d'article tel qu'écrit : « 4 », « 1er », « premier »,
/// « liminaire », « unique », suivi de « bis », « ter »… et d'une lettre
/// majuscule (« 3 bis A », « 1er AA »).
const _number =
    r'(liminaire|premier|unique|\d+(?:er)?)'
    r'((?: (?:[a-z]+ies|bis|ter|quater)\b)?(?: [A-Z]{1,3}\b)?)';

/// Les expressions gardent la casse : la lettre d'un article (« A ») est en
/// majuscule.
final _articleTitle = RegExp("^[Ll]'ar?ticle $_number");
final _amendementTitle = RegExp(r"^[Ll]'amen[a-z]*ment\b");
final _suppressionOf = RegExp("de suppression de l'article $_number");
final _suppressionAmendement = RegExp(r"^[Ll]'amendement de suppression\b");
final _atArticle = RegExp("à l'article $_number");

/// Numéro complet : base et suffixe (« 3 bis A »).
String _numberOf(RegExpMatch m) => '${m.group(1)}${m.group(2) ?? ''}';

/// Un vote au scrutin public sur un article (ou sur la suppression d'un
/// article), d'après le jeu de données ou le site de l'Assemblée.
class ArticleVote {
  const ArticleVote({
    required this.uid,
    required this.numero,
    required this.date,
    required this.titre,
    required this.result,
    required this.number,
    required this.outcome,
    this.dossierRef,
    this.seanceRef,
  });

  /// Le vote du scrutin [s] sur un article, ou `null` si ce n'en est pas un
  /// ([articleVoteOf]).
  static ArticleVote? fromScrutin(Scrutin s) {
    final article = articleVoteOf(s.titre, s.result);
    if (article == null) return null;
    return ArticleVote(
      uid: s.uid,
      numero: s.numero,
      date: s.date,
      titre: s.titre,
      result: s.result,
      number: article.number,
      outcome: article.outcome,
      dossierRef: s.dossierRef,
      seanceRef: s.seanceRef,
    );
  }

  final String uid;
  final int numero;

  /// Jour du vote, à minuit UTC.
  final DateTime date;

  final String titre;
  final VoteResult result;

  /// Numéro de l'article, tel qu'écrit.
  final String number;
  final ArticleOutcome outcome;

  /// Dossier législatif du scrutin ; absent sur le site.
  final String? dossierRef;

  /// Séance du vote ; absente sur le site.
  final String? seanceRef;

  DebatedArticle toArticle() => DebatedArticle(
    number: number,
    outcome: outcome,
    date: date,
    scrutinRef: uid,
  );

  Map<String, Object?> toJson() => {
    'uid': uid,
    'numero': numero,
    'date': formatDate(date),
    'titre': titre,
    'result': result.json,
    'dossierRef': ?dossierRef,
    'seanceRef': ?seanceRef,
  };

  static ArticleVote? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final result = VoteResult.tryParse(json['result']);
    final date = DateTime.tryParse('${json['date']}T00:00:00Z');
    if (json['uid'] is! String ||
        json['numero'] is! int ||
        json['titre'] is! String ||
        result == null ||
        date == null) {
      return null;
    }
    String? optional(Object? v) => v is String && v.isNotEmpty ? v : null;
    return fromScrutin(
      Scrutin(
        uid: json['uid'] as String,
        numero: json['numero'] as int,
        date: date,
        titre: json['titre'] as String,
        codeTypeVote: '',
        libelleTypeVote: '',
        result: result,
        decompte: const Decompte(
          pour: 0,
          contre: 0,
          abstentions: 0,
          nonVotants: 0,
        ),
        dossierRef: optional(json['dossierRef']),
        seanceRef: optional(json['seanceRef']),
        groupVotes: const [],
      ),
    );
  }
}

/// Contenu de [articleVotesKey] : les votes sur les articles des
/// [articleVotesRetention] derniers jours du dernier jeu de données, écrits
/// par le job et relus par les passages de l'agenda et en direct.
class ArticleVotesState {
  const ArticleVotesState({required this.lastNumero, required this.votes});

  /// Garde de [all] (tout le jeu de données) les votes sur les articles
  /// depuis [articleVotesRetention] avant [now].
  factory ArticleVotesState.fromDump(
    Iterable<Scrutin> all, {
    required DateTime now,
  }) {
    final since = parisDay(now).subtract(articleVotesRetention);
    var lastNumero = 0;
    final votes = <ArticleVote>[];
    for (final s in all) {
      if (s.numero > lastNumero) lastNumero = s.numero;
      if (s.date.isBefore(since)) continue;
      if (ArticleVote.fromScrutin(s) case final vote?) votes.add(vote);
    }
    votes.sort((a, b) => a.numero.compareTo(b.numero));
    return ArticleVotesState(lastNumero: lastNumero, votes: votes);
  }

  /// Plus grand numéro du jeu de données : il est complet jusque-là.
  final int lastNumero;

  /// Du plus ancien au plus récent.
  final List<ArticleVote> votes;

  static const _version = 1;

  Map<String, Object?> toJson() => {
    'version': _version,
    'lastNumero': lastNumero,
    'votes': [for (final v in votes) v.toJson()],
  };

  /// Lit l'état, ou `null` s'il est absent ou illisible (avertissement dans
  /// [warnings]).
  static Future<ArticleVotesState?> read(
    ObjectStore store,
    List<String> warnings,
  ) async {
    final raw = await store.read(articleVotesKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?> ||
          json['version'] != _version ||
          json['lastNumero'] is! int ||
          json['votes'] is! List) {
        throw const FormatException('format inattendu');
      }
      return ArticleVotesState(
        lastNumero: json['lastNumero'] as int,
        votes: [
          for (final v in json['votes'] as List) ?ArticleVote.tryFromJson(v),
        ],
      );
    } on Object catch (e) {
      warnings.add('état des votes sur les articles illisible ($e)');
      return null;
    }
  }

  Future<void> write(ObjectStore store) => store.write(
    articleVotesKey,
    jsonEncode(toJson()),
    cacheControl: 'no-store',
  );
}

/// Le bloc « En débat » à l'instant [now] (#55), ou `null` sans texte en
/// débat :
///
/// - séance : la séance de l'Assemblée en cours ou la dernière, commencée
///   dans les [inDebateWindow], dont l'ordre du jour [points] inscrit la
///   discussion (ou la suite de la discussion) d'un texte au dossier connu ;
///   si elle en inscrit plusieurs, celui dont un article a été voté en
///   dernier pendant cette séance, sinon le premier ;
/// - articles : votes de ce dossier sur ses articles ([articleVoteOf]) tirés
///   du jeu de données ([votes], complet jusqu'au scrutin [confirmedUpTo]),
///   dans la même lecture que le dernier vote ; puis votes plus récents lus
///   sur le site ([provisional], sans dossier : rattachés par le texte
///   nommé dans l'intitulé) et ceux du bloc déjà publié ([previous]) que le
///   jeu de données n'a pas encore. Un article par numéro, son dernier vote,
///   du plus récent au plus ancien ;
/// - titre court : même règle que le bloc « À venir » ([pointShortTitle]).
///
/// Les votes à main levée ne sont pas connus (hors périmètre).
InDebate? buildInDebate(
  List<AgendaPoint> points, {
  required DateTime now,
  List<ArticleVote> votes = const [],
  int confirmedUpTo = 0,
  List<ArticleVote> provisional = const [],
  InDebate? previous,
  List<DecisionSummary> decisions = const [],
  DossierIndex? dossiers,
}) {
  final since = now.subtract(inDebateWindow);
  final discussions = [
    for (final p in points)
      if (p.kind == UpcomingKind.discussion &&
          p.dossierRef != null &&
          !p.startsAt.isAfter(now) &&
          p.startsAt.isAfter(since))
        p,
  ];
  if (discussions.isEmpty) return null;
  final latest = discussions.reduce(
    (a, b) => b.startsAt.isAfter(a.startsAt) ? b : a,
  );
  final inSeance = [
    for (final p in discussions)
      if (p.seanceRef == latest.seanceRef) p,
  ];

  // Votes lus sur le site, plus récents que le jeu de données : rattachés
  // au dossier dont un libellé, un vote ou le titre nomme le même texte.
  final fresh = [
    for (final v in provisional)
      if (v.numero > confirmedUpTo) v,
  ];
  List<ArticleVote> votesOf(String dossier) {
    final confirmed = [
      for (final v in votes)
        if (v.dossierRef == dossier && v.numero <= confirmedUpTo) v,
    ];
    final keys = {
      for (final p in points)
        if (p.dossierRef == dossier) ?votedTextKey(p.label),
      for (final v in confirmed) ?votedTextKey(v.titre),
      if (dossiers?.dossier(dossier)?.title case final title?)
        ?votedTextKey(title),
    };
    return [
      ...confirmed,
      for (final v in fresh)
        if (keys.contains(votedTextKey(v.titre))) v,
    ]..sort((a, b) => a.numero.compareTo(b.numero));
  }

  var point = inSeance.first;
  if (inSeance.map((p) => p.dossierRef).toSet().length > 1) {
    final day = parisDay(latest.startsAt);
    var best = 0;
    for (final p in inSeance) {
      for (final v in votesOf(p.dossierRef!)) {
        final inThisSeance = v.seanceRef == null
            ? v.date == day
            : v.seanceRef == latest.seanceRef;
        if (inThisSeance && v.numero > best) {
          best = v.numero;
          point = p;
        }
      }
    }
  }
  final dossier = point.dossierRef!;

  final all = votesOf(dossier);
  final reading = all.isEmpty ? null : _reading(all.last.titre);
  // Article → dernier vote (numéro de scrutin le plus élevé).
  final byArticle = <String, (int, DebatedArticle)>{};
  void add(int numero, DebatedArticle article) {
    final key = _articleKey(article.number);
    final known = byArticle[key];
    if (known == null || numero > known.$1) byArticle[key] = (numero, article);
  }

  for (final v in all) {
    if (_reading(v.titre) == reading) add(v.numero, v.toArticle());
  }
  if (previous != null && previous.dossierRef == dossier) {
    for (final a in previous.articles) {
      final numero = a.scrutinNumero;
      if (numero != null && numero > confirmedUpTo) add(numero, a);
    }
  }
  final articles = byArticle.values.toList()
    ..sort((a, b) => b.$1.compareTo(a.$1));

  return InDebate(
    dossierRef: dossier,
    shortTitle: pointShortTitle(
      point,
      decisions: decisions,
      dossiers: dossiers,
    ),
    dossierUrl: Dossier(uid: dossier, title: '').url,
    seanceRef: latest.seanceRef,
    startsAt: latest.startsAt,
    articles: [for (final (_, a) in articles) a],
  );
}

/// Lecture nommée par la parenthèse finale de l'intitulé (« première
/// lecture »), ou chaîne vide.
String _reading(String titre) =>
    RegExp(r'\(([^()]*)\)\s*\.?\s*$').firstMatch(titre)?.group(1)?.trim() ?? '';

/// Clé d'un article : « premier » et « 1er » désignent le même.
String _articleKey(String number) =>
    number.toLowerCase().replaceFirst(RegExp(r'^premier\b'), '1er');
