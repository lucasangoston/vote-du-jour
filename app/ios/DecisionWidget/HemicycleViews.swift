import SwiftUI
import UIKit

/// Charte Hémicycle (#29) : couleurs claires et sombres, polices Geist et Geist
/// Mono embarquées (`Fonts/`, déclarées dans `Info.plist`), arc du vote et logo.
enum Palette {
  static let surface = dynamic(light: 0xFFFFFF, dark: 0x191C20)
  static let ink = dynamic(light: 0x15181C, dark: 0xECEEF0)
  static let ink2 = dynamic(light: 0x4F5761, dark: 0x9AA2AB)
  static let rule = dynamic(light: 0xE2E5E8, dark: 0x2A2F35)
  static let pour = dynamic(light: 0x1D6B54, dark: 0x4FB08F)
  static let contre = dynamic(light: 0xB4472B, dark: 0xE07A58)
  static let abstention = dynamic(light: 0xAEB4BB, dark: 0x4A5058)

  static func color(_ tint: VoteArc.Tint) -> Color {
    switch tint {
    case .pour: pour
    case .contre: contre
    case .abstention: abstention
    }
  }

  static func color(_ result: WidgetDecision.Result) -> Color {
    color(VoteArc.Tint(result: result))
  }

  private static func dynamic(light: UInt32, dark: UInt32) -> Color {
    Color(
      uiColor: UIColor { traits in
        rgb(traits.userInterfaceStyle == .dark ? dark : light)
      })
  }

  private static func rgb(_ hex: UInt32) -> UIColor {
    UIColor(
      red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
  }
}

extension Font {
  /// Geist (titres en semibold, texte en regular), à la taille de la maquette
  /// et suivant la taille de texte du système.
  static func geist(_ size: CGFloat, semibold: Bool = false, relativeTo style: TextStyle = .body)
    -> Font
  {
    .custom(semibold ? "Geist-SemiBold" : "Geist-Regular", size: size, relativeTo: style)
  }

  /// Geist Mono, pour les chiffres du décompte.
  static func geistMono(_ size: CGFloat, relativeTo style: TextStyle = .caption2) -> Font {
    .custom("GeistMono-Regular", size: size, relativeTo: style)
  }
}

extension WidgetDecision.Result {
  var label: String {
    switch self {
    case .adopte: "Adopté"
    case .rejete: "Rejeté"
    }
  }
}

// MARK: - Géométrie

/// Les dessins suivent le repère des maquettes : une boîte de 120 × 66, le
/// centre du demi-cercle en (60, 60). Les formes se mettent à l'échelle du
/// cadre qu'on leur donne (rapport 120:66).
private enum Hemicycle {
  static let viewBox = CGSize(width: 120, height: 66)
  static let center = CGPoint(x: 60, y: 60)

  static func scale(in rect: CGRect) -> CGFloat {
    min(rect.width / viewBox.width, rect.height / viewBox.height)
  }

  /// Point de l'arc de rayon `radius` à la fraction `t` (0 à gauche, 1 à droite,
  /// en passant par le haut), dans `rect`.
  static func point(_ t: Double, radius: CGFloat, in rect: CGRect) -> CGPoint {
    let s = scale(in: rect)
    let origin = CGPoint(
      x: rect.midX - viewBox.width * s / 2, y: rect.midY - viewBox.height * s / 2)
    let angle = Double.pi * (1 + t)
    return CGPoint(
      x: origin.x + (center.x + radius * CGFloat(cos(angle))) * s,
      y: origin.y + (center.y + radius * CGFloat(sin(angle))) * s)
  }
}

/// Tronçon d'arc plein (bouts droits), de `from` à `to`.
private struct ArcBand: Shape {
  var radius: CGFloat = 50
  var lineWidth: CGFloat
  var from: Double = 0
  var to: Double = 1

  func path(in rect: CGRect) -> Path {
    guard to > from else { return Path() }
    let steps = max(2, Int(((to - from) * 96).rounded(.up)))
    var line = Path()
    for i in 0...steps {
      let t = from + (to - from) * Double(i) / Double(steps)
      let p = Hemicycle.point(t, radius: radius, in: rect)
      if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
    }
    return line.strokedPath(
      StrokeStyle(lineWidth: lineWidth * Hemicycle.scale(in: rect), lineCap: .butt))
  }
}

/// Rangée de points ronds régulièrement espacés sur un arc de rayon `radius`.
private struct ArcDots: Shape {
  var radius: CGFloat
  var diameter: CGFloat
  var spacing: CGFloat

  func path(in rect: CGRect) -> Path {
    let s = Hemicycle.scale(in: rect)
    let d = diameter * s
    var path = Path()
    for t in VoteArc.dotPositions(length: Double.pi * radius, spacing: spacing) {
      let p = Hemicycle.point(t, radius: radius, in: rect)
      path.addEllipse(in: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d))
    }
    return path
  }
}

// MARK: - Vues

/// Arc du vote d'une décision. `lineWidth` est exprimé dans le repère 120 × 66
/// (16 dans les petits arcs des maquettes, 14 dans celui du widget moyen).
struct VoteArcView: View {
  let decision: WidgetDecision
  var lineWidth: CGFloat = 16

  var body: some View {
    ZStack {
      switch VoteArc(decision: decision) {
      case .solid(let tint):
        ArcBand(lineWidth: lineWidth).fill(Palette.color(tint))
      case .dotted(let tint):
        // Pointillés ronds : environ trois quarts de l'épaisseur pleine, neuf
        // points sur le demi-cercle (maquette : 12 pour 16, tous les 19,6).
        ArcDots(radius: 50, diameter: lineWidth * 0.75, spacing: 19.6)
          .fill(Palette.color(tint))
      case .segments(let segments):
        // Du dernier au premier, chacun depuis le début de l'arc : pas de
        // jour entre deux tronçons.
        ForEach(Array(segments.enumerated().reversed()), id: \.offset) { _, segment in
          ArcBand(lineWidth: lineWidth, from: 0, to: segment.to)
            .fill(Palette.color(segment.tint))
        }
      }
    }
    .aspectRatio(120 / 66, contentMode: .fit)
    .accessibilityElement()
    .accessibilityLabel(Self.accessibilityLabel(decision))
  }

  static func accessibilityLabel(_ decision: WidgetDecision) -> String {
    if decision.isMainLevee { return "Vote à main levée" }
    guard let count = decision.count else { return decision.result.label }
    return "\(count.pour) pour, \(count.contre) contre, \(count.abstentions) abstentions"
  }
}

/// Logo Perchoir, « hémicycle en bandes » (#36) : deux arcs épais (encre) et
/// un demi-disque plein (pour) au centre. En-tête du grand widget, état vide.
struct HemicycleLogo: View {
  var color: Color = Palette.ink
  /// Épaisseur des arcs et rayon du demi-disque, en unités de la grille de
  /// 120 : 14 aux tailles des widgets (maquettes Widgets-*.dc.html).
  var weight: CGFloat = 14

  var body: some View {
    ZStack {
      PerchoirArcs(weight: weight).fill(color)
      PerchoirSeat(radius: weight).fill(Palette.pour)
    }
    .aspectRatio(PerchoirFrame.box.width / PerchoirFrame.box.height, contentMode: .fit)
    .accessibilityHidden(true)
  }
}

/// Cadre du logo dans la grille de 120 (viewBox `8 34 104 58` des maquettes),
/// centre des arcs en (60, 86).
private enum PerchoirFrame {
  static let box = CGRect(x: 8, y: 34, width: 104, height: 58)
  static let center = CGPoint(x: 60, y: 86)

  /// Grille → `rect`, à l'échelle et centré.
  static func transform(in rect: CGRect) -> CGAffineTransform {
    let s = min(rect.width / box.width, rect.height / box.height)
    let dx = rect.midX - box.midX * s
    let dy = rect.midY - box.midY * s
    return CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
  }

  /// Demi-cercle supérieur de rayon `radius` (de gauche à droite par le haut).
  static func halfCircle(radius: CGFloat) -> Path {
    var path = Path()
    path.addArc(
      center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(360),
      clockwise: false)
    return path
  }
}

/// Les deux arcs (rayons 46 et 28), bouts droits.
private struct PerchoirArcs: Shape {
  var weight: CGFloat

  func path(in rect: CGRect) -> Path {
    var arcs = Path()
    for radius: CGFloat in [46, 28] {
      arcs.addPath(
        PerchoirFrame.halfCircle(radius: radius)
          .strokedPath(StrokeStyle(lineWidth: weight, lineCap: .butt)))
    }
    return arcs.applying(PerchoirFrame.transform(in: rect))
  }
}

/// Le demi-disque plein du centre.
private struct PerchoirSeat: Shape {
  var radius: CGFloat

  func path(in rect: CGRect) -> Path {
    var seat = PerchoirFrame.halfCircle(radius: radius)
    seat.closeSubpath()
    return seat.applying(PerchoirFrame.transform(in: rect))
  }
}
