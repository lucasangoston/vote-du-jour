import 'package:vote_contract/vote_contract.dart';

import '../decision_status_label.dart';
import '../vote_mode_label.dart';

/// Instantané des dernières décisions, écrit par l'app dans l'espace partagé
/// avec les widgets natifs (App Group sur iOS, SharedPreferences sur Android).
///
/// Les widgets ne connaissent que ce format, pas le contrat publié : l'app
/// décide ici de ce qu'il faut afficher (titre, étape, phrase d'explication),
/// les widgets se contentent du rendu. Un champ optionnel absent n'est pas
/// affiché ; ajouter un champ optionnel ne change pas [version].
///
/// ```json
/// {
///   "version": 1,
///   "savedAt": "2026-10-17T10:17:00.000Z",
///   "decisions": [
///     {
///       "id": "VTANR5L17V8706",
///       "result": "adopte",
///       "date": "2026-10-13",
///       "title": "L'ensemble du projet de loi …",
///       "stage": "1re lecture à l'AN",
///       "explanation": "Le texte prévoit …",
///       "count": {"pour": 503, "contre": 0, "abstentions": 67},
///       "arc": [
///         {"position": "abstention", "n": 66},
///         {"position": "pour", "n": 382},
///         {"position": "abstention", "n": 1},
///         {"position": "pour", "n": 121}
///       ],
///       "voteMode": "scrutin_public",
///       "seats": "ppp-ppa…"
///     }
///   ],
///   "upcomingVotes": [
///     {
///       "id": "RUANR5L17S2027IDS30964PT53289",
///       "startsAt": "2026-10-27T14:00:00.000Z",
///       "title": "Budget de la Sécurité sociale pour 2027"
///     }
///   ]
/// }
/// ```
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.savedAt,
    required this.decisions,
    this.upcomingVotes = const [],
  });

  /// Construit l'instantané à partir de l'index publié : les [maxDecisions]
  /// plus récentes (le grand widget en affichera trois) et les
  /// [maxUpcomingVotes] prochains votes solennels de l'ordre du jour (#56).
  ///
  /// [seats] donne, par identifiant, les sièges de l'hémicycle (#78) des
  /// décisions qui en ont, déjà au format de l'instantané ([encodeSeatVotes]).
  factory WidgetSnapshot.fromIndex(
    DecisionIndex index, {
    required DateTime savedAt,
    int maxDecisions = 3,
    int maxUpcomingVotes = 3,
    Map<String, String> seats = const {},
  }) {
    final votes = [
      for (final u in index.upcoming ?? const <UpcomingItem>[])
        if (u.kind == UpcomingKind.voteSolennel) u,
    ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return WidgetSnapshot(
      savedAt: savedAt,
      decisions: [
        for (final d in index.decisions.take(maxDecisions))
          WidgetDecision.fromSummary(d, seats: seats[d.id]),
      ],
      upcomingVotes: [
        for (final u in votes.take(maxUpcomingVotes))
          WidgetUpcomingVote.fromItem(u),
      ],
    );
  }

  /// Version du format lu par les widgets natifs. Un changement cassant
  /// l'incrémente ; les widgets ignorent une version qu'ils ne connaissent pas.
  static const int version = 1;

  /// Clé de l'instantané dans l'espace partagé (UserDefaults du groupe
  /// d'apps sur iOS, préférences de home_widget sur Android).
  static const String storageKey = 'decisions_snapshot';

  /// Instant d'écriture par l'app.
  final DateTime savedAt;

  /// Décisions, de la plus récente à la plus ancienne.
  final List<WidgetDecision> decisions;

  /// Prochains votes solennels, du plus proche au plus lointain (#56). Les
  /// widgets montrent le premier qui n'est pas passé quand la dernière
  /// décision a plus de trois jours. Champ optionnel : absent d'un instantané
  /// antérieur, et omis s'il est vide.
  final List<WidgetUpcomingVote> upcomingVotes;

  /// Lit un instantané ; renvoie `null` s'il est illisible ou d'une autre
  /// version. Les décisions malformées sont ignorées.
  static WidgetSnapshot? tryFromJson(Object? json) {
    if (json is! Map<String, Object?> || json['version'] != version) {
      return null;
    }
    final savedAt = DateTime.tryParse('${json['savedAt']}');
    final decisions = json['decisions'];
    final upcomingVotes = json['upcomingVotes'];
    if (savedAt == null || decisions is! List) return null;
    return WidgetSnapshot(
      savedAt: savedAt,
      decisions: [
        for (final d in decisions)
          if (d is Map<String, Object?>) ?WidgetDecision.tryFromJson(d),
      ],
      upcomingVotes: [
        if (upcomingVotes is List)
          for (final u in upcomingVotes)
            if (u is Map<String, Object?>) ?WidgetUpcomingVote.tryFromJson(u),
      ],
    );
  }

  /// Sièges de la décision [id] dans cet instantané, s'il les porte.
  String? seatsOf(String id) =>
      decisions.where((d) => d.id == id).firstOrNull?.seats;

  Map<String, Object?> toJson() => {
    'version': version,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'decisions': [for (final d in decisions) d.toJson()],
    if (upcomingVotes.isNotEmpty)
      'upcomingVotes': [for (final u in upcomingVotes) u.toJson()],
  };
}

/// Un vote solennel inscrit à l'ordre du jour, tel que l'affichent les
/// widgets (« Prochain vote solennel », « mar. 27 oct. », titre court ; #56).
class WidgetUpcomingVote {
  const WidgetUpcomingVote({
    required this.id,
    required this.startsAt,
    required this.title,
  });

  factory WidgetUpcomingVote.fromItem(UpcomingItem item) => WidgetUpcomingVote(
    id: item.id,
    startsAt: item.startsAt,
    title: _capitalize(item.shortTitle.trim()),
  );

  /// Identifiant du point de l'ordre du jour.
  final String id;

  /// Début de la séance (instant UTC). Les widgets affichent le jour en heure
  /// de Paris et cessent de montrer le vote le lendemain.
  final DateTime startsAt;

  /// Titre court du texte voté, déjà prêt à afficher.
  final String title;

  static WidgetUpcomingVote? tryFromJson(Map<String, Object?> json) {
    final id = json['id'];
    final startsAt = DateTime.tryParse('${json['startsAt']}');
    final title = json['title'];
    if (id is! String ||
        startsAt == null ||
        title is! String ||
        title.trim().isEmpty) {
      return null;
    }
    return WidgetUpcomingVote(id: id, startsAt: startsAt.toUtc(), title: title);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'startsAt': startsAt.toUtc().toIso8601String(),
    'title': title,
  };
}

/// Une décision telle que l'affichent les widgets.
class WidgetDecision {
  const WidgetDecision({
    required this.id,
    required this.result,
    required this.date,
    required this.title,
    this.stage,
    this.explanation,
    this.count,
    this.voteMode,
    this.arc,
    this.seats,
  });

  /// Les mentions « à main levée » et « provisoire » sont ajoutées à l'étape,
  /// que les widgets antérieurs à #29 affichent déjà ; [voteMode], [count] et
  /// [arc] servent à dessiner l'arc du vote.
  factory WidgetDecision.fromSummary(DecisionSummary d, {String? seats}) =>
      WidgetDecision(
        id: d.id,
        result: d.result,
        date: d.date,
        title: _capitalize(d.compactTitle.trim()),
        stage: _stageWith(d.stage, [
          ?voteModeLabel(d.voteMode),
          ?statusLabel(d.status),
        ]),
        // Phrase du résumé (#9), affichée par le widget moyen.
        explanation: d.explanation?.trim(),
        count: d.count,
        voteMode: d.voteMode,
        arc: d.arc,
        seats: seats,
      );

  /// Identifiant de la décision (deep link vers le détail) : celui du
  /// scrutin, ou de l'acte de décision pour un vote à main levée.
  final String id;

  final VoteResult result;

  /// Jour du vote. Les widgets le formatent eux-mêmes, pour pouvoir passer à
  /// une date relative (« aujourd'hui », « il y a 3 jours ») sans l'app.
  final DateTime date;

  /// Titre principal, déjà prêt à afficher.
  final String title;

  /// Étape de la procédure (« 1re lecture à l'AN »), si connue, suivie de
  /// « · à main levée » pour un vote sans scrutin public et de
  /// « · provisoire » pour une décision pas encore confirmée.
  final String? stage;

  /// Phrase d'explication en langage simple, si disponible.
  final String? explanation;

  /// Décompte du scrutin public (pour, contre, abstentions), pour l'arc du
  /// vote (#29). Absent pour un vote à main levée, ou si l'index publié ne le
  /// donne pas encore : les widgets dessinent alors un arc plein de la
  /// couleur du résultat.
  final VoteTally? count;

  /// Mode de vote (`scrutin_public` ou `main_levee`, #29) : arc en
  /// pointillés pour un vote à main levée. Champ optionnel : absent d'un
  /// instantané antérieur.
  final VoteMode? voteMode;

  /// Arc dans l'ordre de l'hémicycle (#67) : tronçons de gauche à droite,
  /// mêmes règles que `arc` dans l'index. Absent (décision provisoire, index
  /// ou instantané antérieur, arc malformé) : les widgets dessinent l'arc par
  /// sens à partir de [count].
  final List<HemicycleSegment>? arc;

  /// Vote de chaque place de l'hémicycle (#78), au format de
  /// [encodeSeatVotes]. Absent (décision provisoire, à main levée, détail pas
  /// encore lu) : les widgets dessinent l'arc.
  final String? seats;

  static WidgetDecision? tryFromJson(Map<String, Object?> json) {
    final id = json['id'];
    final result = VoteResult.tryParse(json['result']);
    final date = DateTime.tryParse('${json['date']}T00:00:00Z');
    final title = json['title'];
    final stage = json['stage'];
    final explanation = json['explanation'];
    if (id is! String || result == null || date == null || title is! String) {
      return null;
    }
    return WidgetDecision(
      id: id,
      result: result,
      date: date,
      title: title,
      stage: stage is String ? stage : null,
      explanation: explanation is String ? explanation : null,
      count: VoteTally.tryFromJson(json['count']),
      voteMode: VoteMode.tryParse(json['voteMode']),
      arc: HemicycleSegment.tryParseList(json['arc']),
      seats: isSeatVotes(json['seats']) ? json['seats'] as String : null,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'result': result.json,
    'date': formatDate(date),
    'title': title,
    'stage': ?stage,
    'explanation': ?explanation,
    'count': ?count?.toJson(),
    'arc': ?arc?.map((s) => s.toJson()).toList(),
    'voteMode': ?voteMode?.json,
    'seats': ?seats,
  };
}

/// Sièges de l'hémicycle au format de l'instantané (#78) : le caractère de
/// rang `i` est le vote de la place `i + 1` (lettre de [SeatVote.json]), `-`
/// pour une place sans député. Les widgets colorent chaque siège par son vote.
String encodeSeatVotes(List<HemicycleSeat> seats) {
  final byPlace = {for (final s in seats) s.place: s.vote.json};
  final last = byPlace.keys.fold(0, (a, b) => a > b ? a : b);
  return [for (var p = 1; p <= last; p++) byPlace[p] ?? '-'].join();
}

/// Plus que les 650 numéros de place du plan de l'hémicycle.
const _maxSeatPlaces = 1000;

final _seatVotes = RegExp('^[pcanx-]+\$');

/// Vrai pour des sièges lisibles par les widgets (au moins un siège).
bool isSeatVotes(Object? value) =>
    value is String &&
    value.length <= _maxSeatPlaces &&
    _seatVotes.hasMatch(value) &&
    value.contains(RegExp('[^-]'));

/// « 1re lecture à l'AN · provisoire » ; sans étape, « Provisoire ».
String? _stageWith(String? stage, List<String> mentions) {
  if (mentions.isEmpty) return stage;
  final suffix = mentions.join(' · ');
  return stage == null ? _capitalize(suffix) : '$stage · $suffix';
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
