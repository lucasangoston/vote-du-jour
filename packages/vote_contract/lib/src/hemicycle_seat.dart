/// Vote du député assis à une place de l'hémicycle lors d'un scrutin (#71),
/// codé sur une lettre dans le fichier de détail.
enum SeatVote {
  pour('p'),
  contre('c'),
  abstention('a'),

  /// Présent sans prendre part au vote (président de séance, membre du
  /// Gouvernement…).
  nonVotant('n'),

  /// Pas de vote nominatif : député absent.
  absent('x');

  const SeatVote(this.json);

  final String json;

  static SeatVote? tryParse(Object? value) =>
      SeatVote.values.where((v) => v.json == value).firstOrNull;
}

/// Place d'un député dans l'hémicycle et son vote lors d'un scrutin (#71) :
/// la donnée de l'hémicycle « places réelles ».
///
/// Publiée dans le fichier de détail ([DecisionDetail.seats]) sous forme
/// compacte, un tableau `[place, groupe, vote]` par siège :
/// `[63, "PO845401", "p"]`.
class HemicycleSeat {
  const HemicycleSeat({
    required this.place,
    required this.group,
    required this.vote,
  });

  /// Numéro de la place (`placeHemicycle` de l'archive AMO, `numPlace` du
  /// vote nominatif), de la droite de l'hémicycle (1) vers sa gauche.
  final int place;

  /// Référence du groupe politique (organe), par exemple `PO845401` : celle
  /// d'un des groupes du détail ([GroupVoteDetail.organeRef]).
  final String group;

  final SeatVote vote;

  /// Lit les sièges publiés ; `null` s'ils sont absents, vides ou malformés.
  /// Un seul siège illisible (vote inconnu ajouté par un job plus récent,
  /// place manquante, nulle ou en double) rend tous les sièges illisibles :
  /// un hémicycle à trous serait faux. Le lecteur s'en passe alors.
  static List<HemicycleSeat>? tryParseList(Object? json) {
    if (json is! List || json.isEmpty) return null;
    final seats = <HemicycleSeat>[];
    final places = <int>{};
    for (final item in json) {
      if (item is! List || item.length != 3) return null;
      final [place, group, vote] = item;
      final seatVote = SeatVote.tryParse(vote);
      if (place is! int ||
          place <= 0 ||
          !places.add(place) ||
          group is! String ||
          group.isEmpty ||
          seatVote == null) {
        return null;
      }
      seats.add(HemicycleSeat(place: place, group: group, vote: seatVote));
    }
    return seats;
  }

  List<Object?> toJson() => [place, group, vote.json];

  @override
  bool operator ==(Object other) =>
      other is HemicycleSeat &&
      other.place == place &&
      other.group == group &&
      other.vote == vote;

  @override
  int get hashCode => Object.hash(place, group, vote);

  @override
  String toString() => 'HemicycleSeat($place, $group, ${vote.json})';
}
