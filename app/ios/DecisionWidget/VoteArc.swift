import Foundation

/// Arc du vote (charte Hémicycle, #29) : demi-cercle rempli de gauche à droite.
///
/// - Scrutin public avec décompte : pour (vert), puis abstentions (gris), puis
///   contre (brique), proportionnels à pour + contre + abstentions.
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
    self.init(result: decision.result, count: decision.count, mainLevee: decision.isMainLevee)
  }

  init(result: WidgetDecision.Result, count: VoteCount?, mainLevee: Bool) {
    if mainLevee {
      self = .dotted(Tint(result: result))
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
    var segments: [Segment] = []
    var start = 0.0
    for (tint, votes) in [(Tint.pour, count.pour), (.abstention, count.abstentions), (.contre, count.contre)]
    where votes > 0 {
      let end = min(1, start + Double(votes) / total)
      segments.append(Segment(tint: tint, from: start, to: end))
      start = end
    }
    // Le dernier tronçon ferme l'arc malgré les arrondis.
    if let last = segments.popLast() {
      segments.append(Segment(tint: last.tint, from: last.from, to: 1))
    }
    self = .segments(segments)
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
