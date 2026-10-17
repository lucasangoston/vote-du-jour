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
  let decision: WidgetDecision?
}

struct DecisionProvider: TimelineProvider {
  func placeholder(in context: Context) -> DecisionEntry {
    DecisionEntry(date: .now, decision: .sample)
  }

  func getSnapshot(in context: Context, completion: @escaping (DecisionEntry) -> Void) {
    // Dans la galerie, montrer un exemple si l'app n'a encore rien écrit.
    let decision = DecisionSnapshot.load()?.decisions.first
    completion(DecisionEntry(date: .now, decision: decision ?? (context.isPreview ? .sample : nil)))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<DecisionEntry>) -> Void) {
    let entry = DecisionEntry(date: .now, decision: DecisionSnapshot.load()?.decisions.first)
    // L'app recharge le widget dès qu'elle écrit un nouvel instantané ; on
    // redessine aussi à minuit, pour une future date relative.
    let midnight = Calendar.current.nextDate(
      after: .now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime)
    completion(Timeline(entries: [entry], policy: midnight.map { .after($0) } ?? .never))
  }
}

struct DecisionWidgetView: View {
  let entry: DecisionEntry

  var body: some View {
    Group {
      if let decision = entry.decision {
        DecisionView(decision: decision)
      } else {
        EmptyDecisionView()
      }
    }
    .widgetURL(entry.decision?.detailURL ?? listURL)
    .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
  }
}

private struct DecisionView: View {
  let decision: WidgetDecision

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
        Text(decision.dateLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
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
}

struct DecisionWidget: Widget {
  let kind = "DecisionWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: DecisionProvider()) { entry in
      DecisionWidgetView(entry: entry)
    }
    .configurationDisplayName("Dernière décision")
    .description("La dernière décision de l'Assemblée nationale et son résultat.")
    .supportedFamilies([.systemMedium])
  }
}

@main
struct DecisionWidgetBundle: WidgetBundle {
  var body: some Widget {
    DecisionWidget()
  }
}

#Preview(as: .systemMedium) {
  DecisionWidget()
} timeline: {
  DecisionEntry(date: .now, decision: .sample)
  DecisionEntry(
    date: .now,
    decision: WidgetDecision(
      id: "exemple-rejet", result: .rejete, date: "2026-10-01",
      title: "Budget de la Sécurité sociale pour 2027", stage: "1re lecture à l'AN",
      explanation: "La première partie est rejetée : tout le texte tombe."))
  DecisionEntry(date: .now, decision: nil)
}
