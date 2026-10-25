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
/// place : une place par député en exercice ([GroupDirectory.seats], archive
/// AMO), avec le groupe et le vote nominatif de celui qui l'occupe.
///
/// La place d'un votant est celle du vote nominatif (`numPlace`), sinon sa
/// place dans l'archive AMO ; il prend le groupe sous lequel il a voté. Les
/// places sans vote nominatif restent [SeatVote.absent], avec le groupe
/// actuel de leur député. Méthode de `design/maquettes/prep_seats.py`.
///
/// Lève [SeatsMismatch] plutôt que de renvoyer des sièges incohérents :
/// - un votant sans place connue ;
/// - l'effectif d'un groupe (`nombreMembresGroupe`) différent de son nombre
///   de sièges, ou un siège dont le groupe n'a pas pris part au scrutin ;
/// - des nombres de pour, contre ou abstentions différents du décompte
///   publié ;
/// - une place absente du plan ([hemicyclePlanX]), ou les LFI-NFP qui ne
///   siègent pas le plus à gauche, ou le RN pas le plus à droite.
List<HemicycleSeat> hemicycleSeats(Scrutin scrutin, GroupDirectory groups) {
  final seats = <int, HemicycleSeat>{
    for (final s in groups.seats.values)
      if (s.group case final group?)
        s.place: HemicycleSeat(
          place: s.place,
          group: group,
          vote: SeatVote.absent,
        ),
  };
  for (final g in scrutin.groupVotes) {
    for (final v in g.votants) {
      final place = v.place ?? groups.seats[v.acteurRef]?.place;
      if (place == null) {
        throw SeatsMismatch('${v.acteurRef} a voté sans place connue');
      }
      seats[place] = HemicycleSeat(
        place: place,
        group: g.organeRef,
        vote: v.vote,
      );
    }
  }
  final sorted = seats.values.toList()
    ..sort((a, b) => a.place.compareTo(b.place));
  _checkGroups(scrutin, sorted);
  _checkCount(scrutin.decompte, sorted);
  _checkSides(sorted, groups);
  return sorted;
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
