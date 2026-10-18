import SwiftUI
import WidgetKit

/// Lien ouvert par un tap sur le widget : l'app s'ouvre sur la liste. Le
/// paramètre `homeWidget` permet au plugin home_widget de le reconnaître.
private let listURL = URL(string: "votedujour://decisions?homeWidget")!

extension WidgetDecision {
  /// Lien ouvert par un tap sur la décision : son écran de détail
  /// (`votedujour://decisions/<id>?homeWidget`).
  var detailURL: URL {
    var components = URLComponents()
    components.scheme = "votedujour"
    components.host = "decisions"
    components.path = "/\(id)"
    components.queryItems = [URLQueryItem(name: "homeWidget", value: nil)]
    return components.url ?? listURL
  }
}

struct DecisionEntry: TimelineEntry {
  let date: Date
  /// Dernières décisions, de la plus récente à la plus ancienne : trois au
  /// plus, pour le grand widget ; le petit et le moyen n'affichent que la
  /// première.
  let decisions: [WidgetDecision]

  var decision: WidgetDecision? { decisions.first }
}

struct DecisionProvider: TimelineProvider {
  func placeholder(in context: Context) -> DecisionEntry {
    DecisionEntry(date: .now, decisions: WidgetDecision.samples)
  }

  func getSnapshot(in context: Context, completion: @escaping (DecisionEntry) -> Void) {
    // Dans la galerie, montrer un exemple si l'app n'a encore rien écrit.
    let decisions = DecisionSnapshot.load()?.latest(DecisionSnapshot.largeWidgetCount) ?? []
    completion(
      DecisionEntry(
        date: .now,
        decisions: decisions.isEmpty && context.isPreview ? WidgetDecision.samples : decisions))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<DecisionEntry>) -> Void) {
    // Rafraîchi sans l'app toutes les heures, avec une entrée à minuit pour la
    // date relative (voir DecisionFetcher.swift). L'app recharge aussi le widget
    // dès qu'elle écrit un nouvel instantané.
    Task { completion(await DecisionTimeline.make()) }
  }
}

struct DecisionWidgetView: View {
  let entry: DecisionEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    content
      .widgetURL(url)
      .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
  }

  @ViewBuilder
  private var content: some View {
    switch (family, entry.decision) {
    case (_, nil):
      EmptyDecisionView()
    case (.systemSmall, let decision?):
      SmallDecisionView(decision: decision, now: entry.date)
    case (.systemLarge, _):
      LargeDecisionsView(decisions: entry.decisions, now: entry.date)
    case (_, let decision?):
      DecisionView(decision: decision, now: entry.date)
    }
  }

  /// Tap hors d'une ligne : le grand widget ouvre la liste (chaque ligne a
  /// son propre lien), les autres le détail de leur décision.
  private var url: URL {
    family == .systemLarge ? listURL : entry.decision?.detailURL ?? listURL
  }
}

/// Widget moyen : la dernière décision, avec son explication si elle existe.
private struct DecisionView: View {
  let decision: WidgetDecision
  /// Instant d'affichage de l'entrée, pour la date relative.
  let now: Date

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        ResultBadge(result: decision.result)
        if let stage = decision.stage {
          Text(stage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 4)
        RelativeDateText(decision: decision, now: now)
      }
      Text(decision.title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(decision.explanation == nil ? 4 : 2)
        .frame(maxWidth: .infinity, alignment: .leading)
      if let explanation = decision.explanation {
        Text(explanation)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
    }
  }
}

/// Petit widget : badge, titre court et étape ; la date relative à côté du
/// badge quand elle tient sur la même ligne. Pas d'explication.
private struct SmallDecisionView: View {
  let decision: WidgetDecision
  let now: Date

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 4) {
          ResultBadge(result: decision.result)
          Spacer(minLength: 4)
          RelativeDateText(decision: decision, now: now, font: .caption2)
            .fixedSize()
        }
        ResultBadge(result: decision.result)
      }
      Text(decision.title)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(4)
        .minimumScaleFactor(0.85)
        .frame(maxWidth: .infinity, alignment: .leading)
      Spacer(minLength: 0)
      if let stage = decision.stage {
        Text(stage)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
  }
}

/// Grand widget : les trois dernières décisions. Chaque ligne ouvre le détail
/// de sa décision ; le reste du widget (titre, marges) ouvre la liste.
private struct LargeDecisionsView: View {
  let decisions: [WidgetDecision]
  let now: Date

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Dernières décisions")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
      ForEach(Array(decisions.enumerated()), id: \.element.id) { index, decision in
        if index > 0 { Divider() }
        Link(destination: decision.detailURL) {
          DecisionRow(decision: decision, now: now)
        }
      }
      Spacer(minLength: 0)
    }
  }
}

private struct DecisionRow: View {
  let decision: WidgetDecision
  let now: Date

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        ResultBadge(result: decision.result)
        Spacer(minLength: 4)
        RelativeDateText(decision: decision, now: now)
      }
      Text(decision.title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
      // Sur sa propre ligne : « provisoire » ou « à main levée » restent visibles.
      if let stage = decision.stage {
        Text(stage)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

/// Date relative de la décision (« Aujourd'hui », « Il y a 3 jours »).
private struct RelativeDateText: View {
  let decision: WidgetDecision
  let now: Date
  var font: Font = .caption

  var body: some View {
    Text(RelativeDate.label(day: decision.date, now: now))
      .font(font)
      .foregroundStyle(.secondary)
      .lineLimit(1)
  }
}

private struct ResultBadge: View {
  let result: WidgetDecision.Result

  var body: some View {
    let (label, icon, color): (String, String, Color) =
      switch result {
      case .adopte: ("Adopté", "checkmark", .adopted)
      case .rejete: ("Rejeté", "xmark", .rejected)
      }
    Label {
      Text(label).font(.caption.weight(.semibold))
    } icon: {
      Image(systemName: icon).font(.caption2.weight(.bold))
    }
    .labelStyle(BadgeLabelStyle())
    .foregroundStyle(.white)
    .padding(.horizontal, 7)
    .padding(.vertical, 3)
    .background(color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    .fixedSize()
    .accessibilityElement(children: .combine)
    .accessibilityLabel(label)
  }
}

private struct BadgeLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 3) {
      configuration.icon
      configuration.title
    }
  }
}

private struct EmptyDecisionView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Décisions de l'Assemblée")
        .font(.subheadline.weight(.semibold))
      Text("Ouvrez l'app pour charger la dernière décision.")
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension Color {
  /// Mêmes teintes que les badges de l'app (`ResultColors` dans `theme.dart`).
  static let adopted = Color(red: 0x2E / 255, green: 0x7D / 255, blue: 0x32 / 255)
  static let rejected = Color(red: 0xB2 / 255, green: 0x3B / 255, blue: 0x1E / 255)
}

extension WidgetDecision {
  static let sample = WidgetDecision(
    id: "exemple",
    result: .adopte,
    date: "2026-10-13",
    title: "L'ensemble du projet de loi relatif à la simplification de la vie économique.",
    stage: nil,
    explanation: nil
  )

  /// Exemples de la galerie et de l'aperçu (le grand widget en montre trois).
  static let samples = [
    sample,
    WidgetDecision(
      id: "exemple-rejet", result: .rejete, date: "2026-10-08",
      title: "Refonder l'espace Schengen", stage: "Résolution (sans valeur de loi)",
      explanation: nil),
    WidgetDecision(
      id: "exemple-main-levee", result: .adopte, date: "2026-10-07",
      title: "Approbation de l'accord sur l'échange des informations GloBE",
      stage: "1re lecture à l'AN · à main levée", explanation: nil),
  ]
}

struct DecisionWidget: Widget {
  let kind = "DecisionWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: DecisionProvider()) { entry in
      DecisionWidgetView(entry: entry)
    }
    .configurationDisplayName("Dernières décisions")
    .description("Les dernières décisions de l'Assemblée nationale et leur résultat.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

@main
struct DecisionWidgetBundle: WidgetBundle {
  var body: some Widget {
    DecisionWidget()
  }
}

private let previewTimeline: [DecisionEntry] = [
  DecisionEntry(date: .now, decisions: WidgetDecision.samples),
  DecisionEntry(
    date: .now,
    decisions: [
      WidgetDecision(
        id: "exemple-rejet", result: .rejete, date: "2026-10-01",
        title: "Budget de la Sécurité sociale pour 2027",
        stage: "1re lecture à l'AN · provisoire",
        explanation: "La première partie est rejetée : tout le texte tombe.")
    ]),
  DecisionEntry(date: .now, decisions: []),
]

#Preview("Petit", as: .systemSmall) {
  DecisionWidget()
} timeline: {
  for entry in previewTimeline { entry }
}

#Preview("Moyen", as: .systemMedium) {
  DecisionWidget()
} timeline: {
  for entry in previewTimeline { entry }
}

#Preview("Grand", as: .systemLarge) {
  DecisionWidget()
} timeline: {
  for entry in previewTimeline { entry }
}
