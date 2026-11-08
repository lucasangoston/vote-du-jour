import 'package:vote_contract/vote_contract.dart';

import 'group_directory.dart';
import 'hemicycle_plan.dart';
import 'scrutin.dart';

/// Les sièges d'un scrutin ne passent pas les vérifications de
/// [hemicycleSeats] : le job ne les publie pas.
class SeatsMismatch implements Exception {
  const SeatsMismatch(this.message);

  final String message;

  @override
  String toString() => 'SeatsMismatch : $message';
}

/// Sièges du [scrutin] pour l'hémicycle « places réelles » (#71), triés par
/// place : une place par député en exercice le jour du scrutin
/// ([GroupDirectory.seats], archive AMO), avec le groupe et le vote nominatif
/// de celui qui l'occupe.
///
/// La place d'un votant est celle du vote nominatif (`numPlace`), sinon sa
/// place dans l'archive AMO ; il prend le groupe sous lequel il a voté. Les
/// places sans vote nominatif restent [SeatVote.absent], avec le groupe de
/// leur député le jour du scrutin : un député qui a changé de groupe, ou
/// quitté l'Assemblée, depuis, compte là où il était ce jour-là. Méthode de
/// `design/maquettes/prep_seats.py`.
///
/// L'archive AMO ne donne que la place actuelle de chaque député : [history],
/// tirée des votes nominatifs de tous les scrutins, donne sa place le jour du
/// scrutin (un député change parfois de siège, un député parti n'en a plus).
///
/// Lève [SeatsMismatch] plutôt que de renvoyer des sièges incohérents :
/// - un votant sans place connue ;
/// - l'effectif d'un groupe (`nombreMembresGroupe`) différent de son nombre
///   de sièges, ou un siège dont le groupe n'a pas pris part au scrutin ;
/// - des nombres de pour, contre ou abstentions différents du décompte
///   publié ;
/// - une place absente du plan ([hemicyclePlanX]), ou les LFI-NFP qui ne
///   siègent pas le plus à gauche, ou le RN pas le plus à droite.
List<HemicycleSeat> hemicycleSeats(
  Scrutin scrutin,
  GroupDirectory groups, {
  PlaceHistory? history,
}) {
  final day = scrutin.date.toIso8601String().substring(0, 10);
  final seats = <int, HemicycleSeat>{};
  // Les votants dont la place relevée est la leur d'abord, à cette place ;
  // les autres députés ensuite, à leur place habituelle autour du jour du
  // scrutin ([PlaceHistory]), sinon à celle de l'archive AMO, si elle est
  // libre : ceux dont la place est la plus sûre se placent en premier.
  final pending = <_Pending>[];
  final placed = <String>{};
  for (final g in scrutin.groupVotes) {
    for (final v in g.votants) {
      placed.add(v.acteurRef);
      final candidates = [
        if (v.place case final place? when v.usualPlace)
          (place: place, votes: 0, distance: 0),
        ...?history?.placesOn(v.acteurRef, day),
        if (groups.seats[v.acteurRef]?.place case final place?)
          (place: place, votes: 0, distance: _far),
      ];
      if (candidates.isEmpty) {
        throw SeatsMismatch('${v.acteurRef} a voté sans place connue');
      }
      if (v.usualPlace && v.place != null && !seats.containsKey(v.place)) {
        seats[v.place!] = HemicycleSeat(
          place: v.place!,
          group: g.organeRef,
          vote: v.vote,
        );
      } else {
        pending.add((
          acteur: v.acteurRef,
          group: g.organeRef,
          vote: v.vote,
          candidates: candidates,
        ));
      }
    }
  }
  for (final MapEntry(key: acteur, value: s) in groups.seats.entries) {
    if (placed.contains(acteur) || !s.sitsOn(day)) continue;
    if (s.groupOn(day) case final group?) {
      pending.add((
        acteur: acteur,
        group: group,
        vote: SeatVote.absent,
        candidates: [
          ...?history?.placesOn(acteur, day),
          if (s.place case final place?)
            (place: place, votes: 0, distance: _far),
        ],
      ));
    }
  }
  pending.sort(
    (a, b) => _rank(a.candidates.firstOrNull, b.candidates.firstOrNull),
  );
  final absentAt = <int, String>{};
  final unplaced = <String>[];
  for (final p in pending) {
    final place =
        p.candidates
            .map((c) => c.place)
            .where((c) => !seats.containsKey(c))
            .firstOrNull ??
        _nearestFree(p.candidates.firstOrNull?.place, seats);
    if (place != null) {
      seats[place] = HemicycleSeat(place: place, group: p.group, vote: p.vote);
      if (p.vote == SeatVote.absent) absentAt[place] = p.acteur;
    } else {
      unplaced.add(
        '${p.acteur} (${p.group}, ${p.vote.json}, '
        '${p.candidates.map((c) => '${c.place}:${c.votes}').join('/')})',
      );
    }
  }
  _settleGroupChanges(scrutin, seats, absentAt, groups, day);
  final sorted = seats.values.toList()
    ..sort((a, b) => a.place.compareTo(b.place));
  try {
    _checkGroups(scrutin, sorted);
  } on SeatsMismatch catch (e) {
    if (unplaced.isEmpty) rethrow;
    throw SeatsMismatch(
      '${e.message} ; sans siège libre : ${unplaced.join(', ')}',
    );
  }
  _checkCount(scrutin.decompte, sorted);
  _checkSides(sorted, groups);
  return sorted;
}

/// Jours autour d'un changement de groupe où l'effectif publié du scrutin
/// peut encore compter le député dans l'un ou l'autre groupe.
const groupChangeWindow = 15;

/// L'effectif des groupes publié avec le scrutin (`nombreMembresGroupe`) ne
/// suit pas toujours, au jour près, les dates de l'archive AMO : un absent qui
/// a changé de groupe dans les [groupChangeWindow] jours autour du scrutin
/// passe d'un groupe en trop à un groupe qui en manque.
void _settleGroupChanges(
  Scrutin scrutin,
  Map<int, HemicycleSeat> seats,
  Map<int, String> absentAt,
  GroupDirectory groups,
  String day,
) {
  final count = <String, int>{};
  for (final s in seats.values) {
    count[s.group] = (count[s.group] ?? 0) + 1;
  }
  final membres = {for (final g in scrutin.groupVotes) g.organeRef: ?g.membres};
  int gap(String group) => (count[group] ?? 0) - (membres[group] ?? 0);
  for (final MapEntry(key: place, value: acteur) in absentAt.entries) {
    final seat = seats[place]!;
    if (gap(seat.group) <= 0) continue;
    final other = groups.seats[acteur]
        ?.groupsAround(day, groupChangeWindow)
        .where((g) => g != seat.group && gap(g) < 0)
        .firstOrNull;
    if (other == null) continue;
    seats[place] = HemicycleSeat(
      place: place,
      group: other,
      vote: SeatVote.absent,
    );
    count[seat.group] = count[seat.group]! - 1;
    count[other] = (count[other] ?? 0) + 1;
  }
}

/// Effectif de chaque groupe = son nombre de sièges.
void _checkGroups(Scrutin scrutin, List<HemicycleSeat> seats) {
  final bySeats = <String, int>{};
  for (final s in seats) {
    bySeats[s.group] = (bySeats[s.group] ?? 0) + 1;
  }
  final voting = {for (final g in scrutin.groupVotes) g.organeRef};
  if (bySeats.keys.where((g) => !voting.contains(g)) case final extra
      when extra.isNotEmpty) {
    throw SeatsMismatch(
      'sièges de groupes absents du scrutin : ${extra.join(', ')}',
    );
  }
  for (final g in scrutin.groupVotes) {
    final n = bySeats[g.organeRef] ?? 0;
    if (g.membres != n) {
      throw SeatsMismatch(
        'effectif de ${g.organeRef} : ${g.membres} membres, $n sièges',
      );
    }
  }
}

/// Pour, contre et abstentions des sièges = décompte publié.
void _checkCount(Decompte decompte, List<HemicycleSeat> seats) {
  int count(SeatVote vote) => seats.where((s) => s.vote == vote).length;
  final (pour, contre, abstentions) = (
    count(SeatVote.pour),
    count(SeatVote.contre),
    count(SeatVote.abstention),
  );
  if (pour != decompte.pour ||
      contre != decompte.contre ||
      abstentions != decompte.abstentions) {
    throw SeatsMismatch(
      'sièges $pour pour, $contre contre, $abstentions abstentions ; '
      'décompte ${decompte.pour}, ${decompte.contre}, '
      '${decompte.abstentions}',
    );
  }
}

/// Les LFI-NFP le plus à gauche du plan, le RN le plus à droite : abscisse
/// moyenne des sièges de chaque groupe sur [hemicyclePlanX].
void _checkSides(List<HemicycleSeat> seats, GroupDirectory groups) {
  final xs = <String, List<double>>{};
  for (final s in seats) {
    final x = hemicyclePlanX[s.place];
    if (x == null) throw SeatsMismatch('place ${s.place} absente du plan');
    final key = groups[s.group]?.abbreviation ?? s.group;
    xs.putIfAbsent(key, () => []).add(x);
  }
  final means = {
    for (final MapEntry(:key, :value) in xs.entries)
      key: value.reduce((a, b) => a + b) / value.length,
  };
  final byX = means.keys.toList()
    ..sort((a, b) => means[a]!.compareTo(means[b]!));
  if (byX.first != 'LFI-NFP' || byX.last != 'RN') {
    throw SeatsMismatch(
      '${byX.first} le plus à gauche, ${byX.last} le plus à droite '
      '(LFI-NFP et RN attendus)',
    );
  }
}

/// Siège libre du plan le plus proche de [place] (par numéro : les numéros
/// voisins sont sur le même rang), pour un député dont toutes les places
/// relevées sont prises ce jour-là : il siège à côté, dans son groupe.
int? _nearestFree(int? place, Map<int, HemicycleSeat> seats) {
  if (place == null) return null;
  int? best;
  for (final p in hemicyclePlanX.keys) {
    if (seats.containsKey(p)) continue;
    if (best == null || (p - place).abs() < (best - place).abs()) best = p;
  }
  return best;
}

typedef _Pending = ({
  String acteur,
  String group,
  SeatVote vote,
  List<PlaceCandidate> candidates,
});

/// Place candidate d'un député un jour donné : [votes] relevés à cette place
/// dans les [PlaceHistory.window] jours autour, et l'écart en jours du relevé
/// le plus proche.
typedef PlaceCandidate = ({int place, int votes, int distance});

const _far = 1 << 30;

/// Ordre des candidats : le plus de relevés autour du jour, puis le plus
/// proche ; un député sans candidat en dernier.
int _rank(PlaceCandidate? a, PlaceCandidate? b) {
  if (a == null || b == null) return a == null ? (b == null ? 0 : 1) : -1;
  if (a.votes != b.votes) return b.votes.compareTo(a.votes);
  return a.distance.compareTo(b.distance);
}

/// Places des députés au fil de la législature, d'après les votes nominatifs
/// (`numPlace`) des scrutins : l'archive AMO ne donne que la place actuelle,
/// et un député change parfois de siège. Les votes d'un membre du
/// Gouvernement ([NominalVote.usualPlace]) sont ignorés ; un député vote
/// parfois depuis un autre siège (délégation, siège voisin) : la place
/// habituelle est celle du plus de relevés autour du jour.
class PlaceHistory {
  PlaceHistory._(this._byActeur);

  /// Relevés de chaque votant : jours de vote, par place.
  factory PlaceHistory.fromScrutins(Iterable<Scrutin> scrutins) {
    final byActeur = <String, Map<int, Set<int>>>{};
    for (final s in scrutins) {
      final day = _dayNumber(s.date);
      for (final g in s.groupVotes) {
        for (final v in g.votants) {
          if (v.place case final place? when v.usualPlace) {
            byActeur
                .putIfAbsent(v.acteurRef, () => {})
                .putIfAbsent(place, () => {})
                .add(day);
          }
        }
      }
    }
    return PlaceHistory._({
      for (final MapEntry(key: acteur, value: places) in byActeur.entries)
        acteur: {
          for (final MapEntry(key: place, value: days) in places.entries)
            place: days.toList()..sort(),
        },
    });
  }

  /// Demi-largeur, en jours, de la fenêtre où l'on compte les relevés.
  static const window = 30;

  /// Jours de vote (depuis l'époque Unix) de chaque acteur, par place.
  final Map<String, Map<int, List<int>>> _byActeur;

  /// Places relevées pour [acteur] autour du [day] (`AAAA-MM-JJ`), de la
  /// plus sûre à la moins sûre. Vide s'il n'a jamais voté à sa place.
  List<PlaceCandidate> placesOn(String acteur, String day) {
    final target = _dayNumber(DateTime.parse('${day}T00:00:00Z'));
    return [
      for (final MapEntry(key: place, value: days)
          in (_byActeur[acteur] ?? const <int, List<int>>{}).entries)
        (
          place: place,
          votes:
              _lowerBound(days, target + window + 1) -
              _lowerBound(days, target - window),
          distance: _distance(days, target),
        ),
    ]..sort(_rank);
  }

  /// Premier indice de [days] (triés) dont le jour est au moins [day].
  static int _lowerBound(List<int> days, int day) {
    var lo = 0;
    var hi = days.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (days[mid] < day) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Écart entre [target] et le jour le plus proche de [days] (triés).
  static int _distance(List<int> days, int target) {
    final i = _lowerBound(days, target);
    return [
      if (i < days.length) days[i] - target,
      if (i > 0) target - days[i - 1],
    ].reduce((a, b) => a < b ? a : b);
  }
}

int _dayNumber(DateTime date) =>
    date.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
