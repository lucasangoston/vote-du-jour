import Foundation

/// Vote du député assis à une place lors d'un scrutin (#71), codé sur une lettre comme dans le
/// fichier de détail (`HemicycleSeat` du contrat).
enum SeatVote: Character, CaseIterable {
  case pour = "p"
  case contre = "c"
  case abstention = "a"
  /// Présent sans prendre part au vote.
  case nonVotant = "n"
  /// Pas de vote nominatif.
  case absent = "x"
}

/// Votes de l'hémicycle d'une décision (#78), tels que l'instantané les porte : une chaîne dont
/// le caractère de rang `i` est le vote de la place `i + 1` (lettre de `SeatVote`), `-` pour une
/// place sans député. `"pp-ca"` : places 1 et 2 pour, 4 contre, 5 abstention.
///
/// Les widgets colorent chaque siège par son vote, pas par son groupe : à 2 px, la forme d'un
/// siège ne se lit plus.
struct SeatVotes: Equatable {
  /// Vote de chaque place occupée.
  let byPlace: [Int: SeatVote]

  /// Garde-fou : bien plus que les 650 numéros de place du plan.
  static let maxPlaces = 1000
  static let emptyPlace: Character = "-"

  init(byPlace: [Int: SeatVote]) {
    self.byPlace = byPlace
  }

  /// Lit la chaîne de l'instantané ; `nil` si elle est absente, vide, trop longue, ne compte
  /// aucun siège ou contient un caractère inconnu.
  init?(encoded: Any?) {
    guard let text = encoded as? String, !text.isEmpty, text.count <= Self.maxPlaces else {
      return nil
    }
    var byPlace: [Int: SeatVote] = [:]
    for (i, char) in text.enumerated() {
      if char == Self.emptyPlace { continue }
      guard let vote = SeatVote(rawValue: char) else { return nil }
      byPlace[i + 1] = vote
    }
    guard !byPlace.isEmpty else { return nil }
    self.byPlace = byPlace
  }

  /// Lit les sièges du fichier de détail (`seats`, un tableau `[place, groupe, vote]` par
  /// siège), mêmes règles que `HemicycleSeat.tryParseList` : `nil` s'ils sont absents ou vides,
  /// ou si un seul siège est illisible (vote inconnu, place manquante, nulle ou en double,
  /// groupe vide).
  init?(detailSeats json: Any?) {
    guard let items = json as? [Any], !items.isEmpty else { return nil }
    var byPlace: [Int: SeatVote] = [:]
    for item in items {
      guard let seat = item as? [Any], seat.count == 3,
        let place = seat[0] as? NSNumber, CFGetTypeID(place) != CFBooleanGetTypeID(),
        place.doubleValue == place.doubleValue.rounded(), place.intValue > 0,
        place.intValue <= Self.maxPlaces, byPlace[place.intValue] == nil,
        let group = seat[1] as? String, !group.isEmpty,
        let letter = seat[2] as? String, letter.count == 1,
        let vote = SeatVote(rawValue: Character(letter))
      else { return nil }
      byPlace[place.intValue] = vote
    }
    self.byPlace = byPlace
  }

  /// Sièges d'un fichier de détail publié (`v1/decisions/<id>.json`) ; `nil` s'il est
  /// illisible, d'une autre version, d'une autre décision que `id` ou sans sièges.
  static func fromDetail(_ data: Data, id: String) -> SeatVotes? {
    guard
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      root["schemaVersion"] as? Int == 1,
      (root["decision"] as? [String: Any])?["id"] as? String == id
    else { return nil }
    return SeatVotes(detailSeats: root["seats"])
  }

  /// Forme écrite dans l'instantané.
  var encoded: String {
    let last = byPlace.keys.max() ?? 0
    return String((1...max(1, last)).map { byPlace[$0]?.rawValue ?? Self.emptyPlace })
  }
}

/// Sièges à dessiner, groupés par apparence, dans le repère de `HemicycleGeometry`.
struct HemicycleLayout: Equatable {
  /// Apparence d'un siège : la couleur du vote ; l'abstention en plus petit (le vote ne se lit
  /// pas qu'à la teinte), absents et non-votants estompés.
  enum Kind: CaseIterable {
    case pour, contre, abstention, off

    init(_ vote: SeatVote) {
      switch vote {
      case .pour: self = .pour
      case .contre: self = .contre
      case .abstention: self = .abstention
      case .nonVotant, .absent: self = .off
      }
    }

    /// Rayon relatif au siège plein (maquette : abstention à 0,5).
    var radiusScale: Double { self == .abstention ? 0.5 : 1 }
  }

  struct Point: Equatable {
    let x: Double
    let y: Double
  }

  /// Centres des sièges de chaque apparence. Une place inconnue du plan n'est pas dessinée.
  let dots: [Kind: [Point]]

  init(votes: SeatVotes) {
    var dots: [Kind: [Point]] = [:]
    for (i, place) in HemicycleGeometry.places.enumerated() {
      guard let vote = votes.byPlace[place] else { continue }
      dots[Kind(vote), default: []].append(
        Point(x: HemicycleGeometry.xs[i], y: HemicycleGeometry.ys[i]))
    }
    self.dots = dots
  }

  /// Nombre de sièges dessinés.
  var count: Int { dots.values.reduce(0) { $0 + $1.count } }
}
