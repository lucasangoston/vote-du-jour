import SwiftUI
import UIKit

/// Charte (DESIGN.md, système inspiré de Wired) : couleurs claires et
/// sombres, polices Geist et Newsreader embarquées (`Fonts/`, déclarées dans
/// `Info.plist`), hémicycle, arc du vote et logo. L'interface est en noir,
/// blanc et gris ; seules les données (vote, résultat) portent une couleur.
enum Palette {
  /// Fond du widget : la surface douce de l'app.
  static let surface = dynamic(light: 0xF5F5F5, dark: 0x121212)
  /// Bande du prochain vote du grand widget.
  static let raised = dynamic(light: 0xEBEBEB, dark: 0x1F1F1F)
  static let ink = dynamic(light: 0x000000, dark: 0xFFFFFF)
  static let ink2 = dynamic(light: 0x6B6B6B, dark: 0x9E9E9E)
  static let rule = dynamic(light: 0xE0E0E0, dark: 0x2A2A2A)
  /// Texte du résultat et des chiffres du décompte (inchangés).
  static let pour = dynamic(light: 0x1D6B54, dark: 0x4FB08F)
  static let contre = dynamic(light: 0xB4472B, dark: 0xE07A58)
  /// Sièges absents et non-votants, à 28 % d'opacité.
  static let seatOff = dynamic(light: 0xAEB4BB, dark: 0x4A5058).opacity(0.28)

  /// Couleurs du vote (revue UI/UX, #78) : sièges, arc et symboles du
  /// décompte. Pour foncé et contre clair de jour, l'inverse de nuit,
  /// abstention en gris moyen : distincts en deutéranopie simulée, à 3:1 au
  /// moins contre la surface.
  static let votePour = dynamic(light: 0x1D6B54, dark: 0x4FB08F)
  static let voteContre = dynamic(light: 0xE0683A, dark: 0xB5461F)
  static let voteAbstention = dynamic(light: 0x8D949A, dark: 0x9AA2AB)

  static func vote(_ tint: VoteArc.Tint) -> Color {
    switch tint {
    case .pour: votePour
    case .contre: voteContre
    case .abstention: voteAbstention
    }
  }

  /// « Adopté » couleur pour, « Rejeté » couleur contre.
  static func color(_ result: WidgetDecision.Result) -> Color {
    result == .adopte ? pour : contre
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

/// Instances de Newsreader embarquées.
enum NewsreaderWeight: String {
  case regular = "NewsreaderRoman-Regular"
}

extension Font {
  /// Geist (titres en semibold, texte en regular), à la taille de la maquette
  /// et suivant la taille de texte du système.
  static func geist(_ size: CGFloat, semibold: Bool = false, relativeTo style: TextStyle = .body)
    -> Font
  {
    .custom(semibold ? "Geist-SemiBold" : "Geist-Regular", size: size, relativeTo: style)
  }

  /// Geist en graisse moyenne (titre du petit widget, chiffres du décompte).
  static func geistMedium(_ size: CGFloat, relativeTo style: TextStyle = .body) -> Font {
    .custom("Geist-Medium", size: size, relativeTo: style)
  }

  /// Newsreader en graisse 400 (police variable, instance nommée par son nom
  /// PostScript), pour le résultat, les titres des widgets moyen et grand et
  /// le jour du prochain vote (#78, DESIGN.md).
  static func newsreader(
    _ size: CGFloat, weight: NewsreaderWeight = .regular, relativeTo style: TextStyle = .title3
  ) -> Font {
    .custom(weight.rawValue, size: size, relativeTo: style)
  }
}

/// Typographie des widgets, en un seul endroit (#78) : polices, graisses et
/// tailles des titres. Une autre charte ne change que ces valeurs. Affichage
/// en Newsreader 400, structure en Geist (DESIGN.md).
enum WidgetTheme {
  /// Mot du résultat (« Adopté ») : petit et moyen, grand.
  static let resultSize: CGFloat = 20
  static let largeResultSize: CGFloat = 24
  /// Titres courts : petit widget (Geist), moyen et grand (Newsreader).
  static let smallTitleSize: CGFloat = 14
  static let mediumTitleSize: CGFloat = 19
  static let largeTitleSize: CGFloat = 22
  /// Jour du prochain vote : petit et moyen, bande du grand.
  static let daySize: CGFloat = 40
  static let bandDaySize: CGFloat = 30
  /// Lignes secondaires (« Vote · mar. 15 h », date, mois).
  static let metaSize: CGFloat = 13
  static let monthSize: CGFloat = 12
  /// Rétrécissement toléré des titres aux grandes tailles de texte.
  static let minimumScale: CGFloat = 0.8

  /// Mot du résultat et titres des widgets moyen et grand.
  static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title3) -> Font {
    .newsreader(size, relativeTo: style)
  }

  /// Jour du prochain vote.
  static func day(_ size: CGFloat) -> Font {
    .newsreader(size, relativeTo: .largeTitle)
  }

  /// Titre court du petit widget et de la bande du prochain vote.
  static func title(_ size: CGFloat, semibold: Bool = false) -> Font {
    semibold
      ? .geist(size, semibold: true, relativeTo: .subheadline)
      : .geistMedium(size, relativeTo: .subheadline)
  }

  /// Lignes secondaires.
  static func meta(_ size: CGFloat = metaSize) -> Font {
    .geist(size, relativeTo: .footnote)
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
        ArcBand(lineWidth: lineWidth).fill(Palette.vote(tint))
      case .dotted(let tint):
        // Pointillés ronds : environ trois quarts de l'épaisseur pleine, neuf
        // points sur le demi-cercle (maquette : 12 pour 16, tous les 19,6).
        ArcDots(radius: 50, diameter: lineWidth * 0.75, spacing: 19.6)
          .fill(Palette.vote(tint))
      case .segments(let segments):
        // Du dernier au premier, chacun depuis le début de l'arc : pas de
        // jour entre deux tronçons.
        ForEach(Array(segments.enumerated().reversed()), id: \.offset) { _, segment in
          ArcBand(lineWidth: lineWidth, from: 0, to: segment.to)
            .fill(Palette.vote(segment.tint))
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

/// Hémicycle d'une décision (#78) : chaque place du plan de l'Assemblée,
/// colorée par le vote de son député. Sans sièges, l'arc du vote.
struct DecisionHemicycleView: View {
  let decision: WidgetDecision
  /// Épaisseur de l'arc de repli, dans le repère 120 × 66.
  var arcLineWidth: CGFloat = 16

  var body: some View {
    if let seats = decision.seats {
      HemicycleSeatsView(layout: HemicycleLayout(votes: seats))
    } else {
      VoteArcView(decision: decision, lineWidth: arcLineWidth)
    }
  }
}

/// Les sièges, un calque par apparence : estompés dessous, puis pour, contre
/// et abstention (en plus petit).
struct HemicycleSeatsView: View {
  let layout: HemicycleLayout

  var body: some View {
    ZStack {
      SeatDots(points: layout.dots[.off] ?? []).fill(Palette.seatOff)
      SeatDots(points: layout.dots[.pour] ?? []).fill(Palette.votePour)
      SeatDots(points: layout.dots[.contre] ?? []).fill(Palette.voteContre)
      SeatDots(points: layout.dots[.abstention] ?? [], radiusScale: 0.5)
        .fill(Palette.voteAbstention)
    }
    .aspectRatio(
      HemicycleGeometry.viewBox.width / HemicycleGeometry.viewBox.height, contentMode: .fit
    )
    // Décrit par le widget (résultat, titre, totaux).
    .accessibilityHidden(true)
  }
}

/// Sièges ronds aux centres `points` (repère `HemicycleGeometry`), à l'échelle
/// du cadre et centrés.
private struct SeatDots: Shape {
  let points: [HemicycleLayout.Point]
  var radiusScale: Double = 1

  func path(in rect: CGRect) -> Path {
    let box = HemicycleGeometry.viewBox
    let s = min(rect.width / box.width, rect.height / box.height)
    let dx = rect.midX - (box.x + box.width / 2) * s
    let dy = rect.midY - (box.y + box.height / 2) * s
    let r = HemicycleGeometry.seatRadius * radiusScale * s
    var path = Path()
    for p in points {
      path.addEllipse(in: CGRect(x: p.x * s + dx - r, y: p.y * s + dy - r, width: 2 * r, height: 2 * r))
    }
    return path
  }
}

/// Arc vide du prochain vote : deux bandes couleur filet (maquette : viewBox
/// 300 × 162, rayons 128 et 98, épaisseur 18).
struct EmptyArcView: View {
  var body: some View {
    EmptyArc()
      .fill(Palette.rule)
      .aspectRatio(300 / 162, contentMode: .fit)
      .accessibilityHidden(true)
  }

  private struct EmptyArc: Shape {
    func path(in rect: CGRect) -> Path {
      let s = min(rect.width / 300, rect.height / 162)
      let origin = CGPoint(x: rect.midX - 150 * s, y: rect.midY - 81 * s)
      var bands = Path()
      for radius: CGFloat in [128, 98] {
        var arc = Path()
        arc.addArc(
          center: CGPoint(x: origin.x + 150 * s, y: origin.y + 150 * s), radius: radius * s,
          startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        bands.addPath(arc.strokedPath(StrokeStyle(lineWidth: 18 * s, lineCap: .butt)))
      }
      return bands
    }
  }
}

/// Décompte sans mots : la forme dit le vote (rond plein pour, anneau contre,
/// petit point abstention), dans la couleur du vote ; le chiffre suit, dans
/// la couleur de texte habituelle.
struct TallyView: View {
  let count: VoteCount
  var size: CGFloat = 13

  var body: some View {
    HStack(spacing: 10) {
      item(.pour, count.pour, Palette.pour)
      item(.contre, count.contre, Palette.contre)
      item(.abstention, count.abstentions, Palette.ink2)
    }
    .font(.geistMedium(size, relativeTo: .footnote))
    .monospacedDigit()
    .lineLimit(1)
    .minimumScaleFactor(0.8)
    .accessibilityElement()
    .accessibilityLabel(
      "\(count.pour) pour, \(count.contre) contre, \(count.abstentions) abstentions")
  }

  private func item(_ tint: VoteArc.Tint, _ n: Int, _ color: Color) -> some View {
    HStack(spacing: 4) {
      Glyph(tint: tint).frame(width: size * 0.9, height: size * 0.9)
      Text("\(n)").foregroundStyle(color)
    }
  }

  /// Glyphes de la maquette (cadre de 12) : rond de rayon 5, anneau de rayon 4
  /// et d'épaisseur 2, point de rayon 2,2.
  private struct Glyph: View {
    let tint: VoteArc.Tint

    var body: some View {
      GeometryReader { proxy in
        let unit = min(proxy.size.width, proxy.size.height) / 12
        ZStack {
          switch tint {
          case .pour: Circle().fill(Palette.votePour).frame(width: 10 * unit, height: 10 * unit)
          case .contre:
            Circle().stroke(Palette.voteContre, lineWidth: 2 * unit)
              .frame(width: 8 * unit, height: 8 * unit)
          case .abstention:
            Circle().fill(Palette.voteAbstention).frame(width: 4.4 * unit, height: 4.4 * unit)
          }
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
      }
    }
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
