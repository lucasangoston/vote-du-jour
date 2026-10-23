import Foundation

/// Arc du vote (charte Hémicycle, #29) : demi-cercle rempli de gauche à droite.
///
/// - Scrutin public avec arc dans l'ordre de l'hémicycle (#67) : ses tronçons,
///   groupes de gauche à gauche, proportionnels aux voix.
/// - Scrutin public avec décompte seulement (décision provisoire, instantané
///   ancien) : pour (vert), puis abstentions (gris), puis contre (brique),
///   proportionnels à pour + contre + abstentions.
/// - Vote à main levée : pointillés ronds couleur du résultat.
/// - Sans décompte : arc plein couleur du résultat.
///
/// Logique pure, compilée aussi dans `RunnerTests` pour ses tests ; le dessin
/// est dans `HemicycleViews.swift`.
enum VoteArc: Equatable {
  /// Rôle de couleur d'un tronçon.
  enum Tint: Equatable {
    case pour, contre, abstention

    init(result: WidgetDecision.Result) {
      self = result == .adopte ? .pour : .contre
    }

    /// Sens d'un tronçon de l'arc de l'hémicycle (`pour`, `abstention`,
    /// `contre`) ; `nil` pour une valeur inconnue.
    init?(json: String) {
      switch json {
      case "pour": self = .pour
      case "abstention": self = .abstention
      case "contre": self = .contre
      default: return nil
      }
    }

    var json: String {
      switch self {
      case .pour: "pour"
      case .abstention: "abstention"
      case .contre: "contre"
      }
    }
  }

  /// Tronçon de l'arc, en fraction de sa longueur (0 à gauche, 1 à droite).
  struct Segment: Equatable {
    let tint: Tint
    let from: Double
    let to: Double
  }

  case segments([Segment])
  case dotted(Tint)
  case solid(Tint)

  init(decision: WidgetDecision) {
    self.init(
      result: decision.result, count: decision.count, mainLevee: decision.isMainLevee,
      hemicycle: decision.arc)
  }

  init(
    result: WidgetDecision.Result, count: VoteCount?, mainLevee: Bool,
    hemicycle: [HemicyclePart]? = nil
  ) {
    if mainLevee {
      self = .dotted(Tint(result: result))
      return
    }
    if let hemicycle, !hemicycle.isEmpty {
      self = .segments(Self.segments(hemicycle.map { ($0.tint, $0.n) }))
      return
    }
    guard let count else {
      self = .solid(Tint(result: result))
      return
    }
    let total = Double(count.pour + count.contre + count.abstentions)
    guard total > 0 else {
      self = .solid(Tint(result: result))
      return
    }
    self = .segments(
      Self.segments([
        (.pour, count.pour), (.abstention, count.abstentions), (.contre, count.contre),
      ]))
  }

  /// Tronçons proportionnels aux voix, de gauche à droite ; les parts vides
  /// sont omises.
  private static func segments(_ parts: [(Tint, Int)]) -> [Segment] {
    let total = Double(parts.reduce(0) { $0 + max(0, $1.1) })
    guard total > 0 else { return [] }
    var segments: [Segment] = []
    var start = 0.0
    for (tint, votes) in parts where votes > 0 {
      let end = min(1, start + Double(votes) / total)
      segments.append(Segment(tint: tint, from: start, to: end))
      start = end
    }
    // Le dernier tronçon ferme l'arc malgré les arrondis.
    if let last = segments.popLast() {
      segments.append(Segment(tint: last.tint, from: last.from, to: 1))
    }
    return segments
  }

  /// Positions de points ronds régulièrement espacés sur un arc de longueur
  /// `length`, à environ `spacing` les uns des autres, les deux extrémités
  /// comprises (rangées symétriques). Deux points au moins.
  static func dotPositions(length: Double, spacing: Double) -> [Double] {
    guard length > 0, spacing > 0 else { return [0, 1] }
    let gaps = max(1, Int((length / spacing).rounded()))
    return (0...gaps).map { Double($0) / Double(gaps) }
  }
}

/// Tronçon de l'arc dans l'ordre de l'hémicycle (#67) : `{"position": "pour",
/// "n": 382}`, `n` strictement positif.
struct HemicyclePart: Equatable {
  let tint: VoteArc.Tint
  let n: Int

  init(_ tint: VoteArc.Tint, _ n: Int) {
    self.tint = tint
    self.n = n
  }

  /// Lit un arc (liste de tronçons de gauche à droite) dans un objet issu de
  /// `JSONSerialization` ou de l'instantané, mêmes règles que
  /// `HemicycleSegment.tryParseList` : `nil` s'il est absent ou vide, ou si un
  /// seul tronçon est illisible (sens inconnu, nombre manquant, non entier,
  /// nul ou négatif).
  static func parse(_ json: Any?) -> [HemicyclePart]? {
    guard let items = json as? [Any], !items.isEmpty else { return nil }
    var parts: [HemicyclePart] = []
    for item in items {
      guard let dict = item as? [String: Any],
        let tint = (dict["position"] as? String).flatMap(VoteArc.Tint.init(json:)),
        let n = dict["n"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
        n.doubleValue == n.doubleValue.rounded(), n.intValue > 0
      else { return nil }
      parts.append(HemicyclePart(tint, n.intValue))
    }
    return parts
  }

  /// Forme écrite dans l'instantané.
  var json: [String: Any] { ["position": tint.json, "n": n] }
}
