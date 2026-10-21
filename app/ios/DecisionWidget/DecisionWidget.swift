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
  /// Prochains votes solennels de l'instantané (#56).
  var upcomingVotes: [UpcomingVote] = []

  var decision: WidgetDecision? { decisions.first }

  /// Vote solennel à annoncer à l'instant de l'entrée : la dernière décision
  /// a plus de trois jours (ou il n'y en a pas) et le vote n'est pas passé.
  var upcomingVote: UpcomingVote? {
    UpcomingVote.shown(among: upcomingVotes, latestDecisionDay: decision?.date, now: date)
  }
}

struct DecisionProvider: TimelineProvider {
  func placeholder(in context: Context) -> DecisionEntry {
    DecisionEntry(date: .now, decisions: WidgetDecision.samples)
  }

  func getSnapshot(in context: Context, completion: @escaping (DecisionEntry) -> Void) {
    // Dans la galerie, montrer un exemple si l'app n'a encore rien écrit.
    let snapshot = DecisionSnapshot.load()
    let decisions = snapshot?.latest(DecisionSnapshot.largeWidgetCount) ?? []
    completion(
      DecisionEntry(
        date: .now,
        decisions: decisions.isEmpty && context.isPreview ? WidgetDecision.samples : decisions,
        upcomingVotes: snapshot?.upcomingVotes ?? []))
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
      .padding(padding)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .widgetURL(url)
      .containerBackground(for: .widget) { Palette.surface }
  }

  @ViewBuilder
  private var content: some View {
    // Sans décision récente, le petit et le moyen widget annoncent le
    // prochain vote solennel ; le grand l'ajoute sous ses décisions.
    switch (family, entry.decision, entry.upcomingVote) {
    case (.systemSmall, _, let vote?):
      SmallUpcomingView(vote: vote)
    case (.systemMedium, _, let vote?):
      UpcomingView(vote: vote)
    case (_, nil, _):
      EmptyDecisionView()
    case (.systemSmall, let decision?, _):
      SmallDecisionView(decision: decision, now: entry.date)
    case (.systemLarge, _, let vote):
      LargeDecisionsView(decisions: entry.decisions, upcomingVote: vote, now: entry.date)
    case (_, let decision?, _):
      DecisionView(decision: decision, now: entry.date)
    }
  }

  /// Marges des maquettes (les marges système sont désactivées).
  private var padding: EdgeInsets {
    switch family {
    case .systemSmall: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
    case .systemLarge: EdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16)
    default: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
    }
  }

  /// Tap hors d'une ligne : le grand widget ouvre la liste (chaque ligne a
  /// son propre lien), les autres le détail de leur décision, ou la liste
  /// quand ils annoncent le prochain vote.
  private var url: URL {
    if family == .systemLarge || entry.upcomingVote != nil { return listURL }
    return entry.decision?.detailURL ?? listURL
  }
}

/// « Prochain vote solennel » (#56).
private let upcomingKicker = "Prochain vote solennel"

/// Petit widget sans décision récente : « Prochain vote solennel », le jour
/// (« Mar. 27 oct. ») à la place de l'arc, puis le titre court.
private struct SmallUpcomingView: View {
  let vote: UpcomingVote

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      MetaText(text: upcomingKicker)
        .minimumScaleFactor(0.85)
      Text(metaLine([vote.dayLabel]))
        .font(.geist(20, semibold: true, relativeTo: .title3))
        .tracking(-0.2)
        .foregroundStyle(Palette.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      Spacer(minLength: 6)
      DecisionTitle(text: vote.title, lineLimit: 4, lineSpacing: 0)
    }
    .accessibilityElement(children: .combine)
  }
}

/// Jour du vote en colonne (« mar. », « 27 », « oct. »), à la place de l'arc
/// du widget moyen.
private struct UpcomingDay: View {
  let vote: UpcomingVote

  var body: some View {
    VStack(spacing: 0) {
      Text(vote.weekdayLabel)
        .font(.geist(13, relativeTo: .footnote))
        .foregroundStyle(Palette.ink2)
      Text(vote.dayOfMonthLabel)
        .font(.geist(34, semibold: true, relativeTo: .title))
        .tracking(-0.68)
        .foregroundStyle(Palette.ink)
      Text(vote.monthLabel)
        .font(.geist(13, relativeTo: .footnote))
        .foregroundStyle(Palette.ink2)
    }
    .lineLimit(1)
    .accessibilityElement(children: .combine)
  }
}

/// Widget moyen sans décision récente : le jour du vote dans la colonne de
/// l'arc, « Prochain vote solennel » et le titre court à droite.
private struct UpcomingView: View {
  let vote: UpcomingVote

  var body: some View {
    HStack(spacing: 14) {
      UpcomingDay(vote: vote).frame(width: 92)
      VStack(alignment: .leading, spacing: 5) {
        MetaText(text: upcomingKicker)
        DecisionTitle(text: vote.title, size: 14.5, lineLimit: 3)
      }
      .frame(maxHeight: .infinity)
    }
    .frame(maxHeight: .infinity)
    .accessibilityElement(children: .combine)
  }
}

/// Ligne du grand widget sous les décisions : le jour à la place de l'arc,
/// le titre court, puis « Prochain vote solennel · mar. 27 oct. ».
private struct UpcomingRow: View {
  let vote: UpcomingVote

  var body: some View {
    HStack(spacing: 12) {
      VStack(spacing: -2) {
        Text(vote.dayOfMonthLabel)
          .font(.geist(17, semibold: true, relativeTo: .body))
          .foregroundStyle(Palette.ink)
        Text(vote.monthLabel)
          .font(.geist(11, relativeTo: .caption2))
          .foregroundStyle(Palette.ink2)
      }
      .lineLimit(1)
      .frame(width: 48)
      VStack(alignment: .leading, spacing: 3) {
        DecisionTitle(text: vote.title, lineLimit: 2)
        MetaText(text: "\(upcomingKicker) · \(vote.dayLabel)")
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

/// Parties d'une ligne d'informations jointes par « · », initiale en majuscule.
private func metaLine(_ parts: [String?]) -> String {
  let line = parts.compactMap { $0 }.joined(separator: " · ")
  return line.prefix(1).uppercased() + line.dropFirst()
}

/// Titre de décision : Geist semibold, interlettrage serré.
private struct DecisionTitle: View {
  let text: String
  var size: CGFloat = 14
  var lineLimit: Int
  var lineSpacing: CGFloat = 1.5

  var body: some View {
    Text(text)
      .font(.geist(size, semibold: true, relativeTo: .subheadline))
      .tracking(-0.01 * size)
      .lineSpacing(lineSpacing)
      .foregroundStyle(Palette.ink)
      .lineLimit(lineLimit)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Ligne secondaire (étape, mentions, date relative).
private struct MetaText: View {
  let text: String
  var lineLimit = 1

  var body: some View {
    Text(text)
      .font(.geist(11.5, relativeTo: .caption))
      .foregroundStyle(Palette.ink2)
      .lineLimit(lineLimit)
  }
}

/// Petit widget : arc en haut à gauche, résultat coloré à droite, titre (4
/// lignes au plus), puis mentions et date relative si la place le permet : le
/// titre passe avant.
private struct SmallDecisionView: View {
  let decision: WidgetDecision
  let now: Date

  var body: some View {
    ViewThatFits(in: .vertical) {
      content(showsDate: true)
      content(showsDate: false)
    }
  }

  private func content(showsDate: Bool) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .bottom) {
        VoteArcView(decision: decision).frame(width: 58, height: 32)
        Spacer(minLength: 4)
        Text(decision.result.label)
          .font(.geist(12, semibold: true, relativeTo: .caption))
          .foregroundStyle(Palette.color(decision.result))
          .fixedSize()
      }
      Spacer(minLength: 4)
      DecisionTitle(text: decision.title, lineLimit: 4, lineSpacing: 0)
      Spacer(minLength: 4)
      let date = RelativeDate.inlineLabel(day: decision.date, now: now)
      let parts = decision.mentions + (showsDate ? [date] : [])
      if !parts.isEmpty {
        MetaText(text: metaLine(parts), lineLimit: 2)
      }
    }
  }
}

/// Widget moyen : colonne arc, résultat et chiffres, puis étape et date,
/// titre et explication sur deux lignes.
private struct DecisionView: View {
  let decision: WidgetDecision
  /// Instant d'affichage de l'entrée, pour la date relative.
  let now: Date

  var body: some View {
    HStack(spacing: 14) {
      VStack(spacing: 6) {
        VoteArcView(decision: decision, lineWidth: 14).frame(width: 92, height: 51)
        Text(decision.result.label)
          .font(.geist(13, semibold: true, relativeTo: .footnote))
          .foregroundStyle(Palette.color(decision.result))
        if let count = decision.count, !decision.isMainLevee {
          Text("\(count.pour) · \(count.contre) · \(count.abstentions)")
            .font(.geistMono(10.5))
            .foregroundStyle(Palette.ink2)
            .accessibilityLabel(VoteArcView.accessibilityLabel(decision))
        } else if decision.isMainLevee {
          Text("À main levée")
            .font(.geist(10.5, relativeTo: .caption2))
            .foregroundStyle(Palette.ink2)
        }
      }
      .lineLimit(1)
      .frame(width: 92)
      ViewThatFits(in: .vertical) {
        details(explanationLines: 2)
        details(explanationLines: 1)
        details(explanationLines: 0)
      }
    }
    .frame(maxHeight: .infinity)
  }

  private func details(explanationLines: Int) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      // La mention « à main levée » est déjà sous l'arc.
      MetaText(
        text: metaLine([
          decision.stageWithoutMentions,
          decision.isProvisional ? WidgetDecision.provisionalMention : nil,
          RelativeDate.inlineLabel(day: decision.date, now: now),
        ]))
      DecisionTitle(
        text: decision.title, size: 14.5,
        lineLimit: decision.explanation == nil || explanationLines == 0 ? 4 : 2)
      if let explanation = decision.explanation, explanationLines > 0 {
        Text(explanation)
          .font(.geist(12, relativeTo: .caption))
          .lineSpacing(2.5)
          .foregroundStyle(Palette.ink2)
          .lineLimit(explanationLines)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(maxHeight: .infinity)
  }
}

/// Grand widget : en-tête (logo, « Dernières décisions ») puis les trois
/// dernières décisions. Chaque ligne ouvre le détail de sa décision ; le reste
/// du widget (en-tête, marges) ouvre la liste.
private struct LargeDecisionsView: View {
  let decisions: [WidgetDecision]
  /// Prochain vote solennel, ajouté en quatrième ligne (#56).
  var upcomingVote: UpcomingVote?
  let now: Date

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        HemicycleLogo().frame(width: 22, height: 12)
        Text("Dernières décisions")
          .font(.geist(12, semibold: true, relativeTo: .caption))
          .foregroundStyle(Palette.ink2)
      }
      .padding(.bottom, 6)
      .accessibilityElement(children: .combine)
      // Trois emplacements de même hauteur, même s'il y a moins de décisions.
      ForEach(0..<DecisionSnapshot.largeWidgetCount, id: \.self) { index in
        Group {
          if index < decisions.count {
            Link(destination: decisions[index].detailURL) {
              DecisionRow(decision: decisions[index], now: now)
            }
          } else {
            Color.clear
          }
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) {
          if index + 1 < min(decisions.count, DecisionSnapshot.largeWidgetCount)
            || (upcomingVote != nil && index + 1 == decisions.count)
          {
            Rectangle().fill(Palette.rule).frame(height: 1)
          }
        }
      }
      // Hors des liens des décisions : le tap ouvre la liste.
      if let upcomingVote {
        UpcomingRow(vote: upcomingVote).frame(maxHeight: .infinity)
      }
    }
  }
}

private struct DecisionRow: View {
  let decision: WidgetDecision
  let now: Date

  var body: some View {
    HStack(spacing: 12) {
      VoteArcView(decision: decision).frame(width: 48, height: 27)
      VStack(alignment: .leading, spacing: 3) {
        DecisionTitle(text: decision.title, lineLimit: 2)
        // « provisoire » et « à main levée » restent visibles.
        let rest = (decision.mentions + [RelativeDate.inlineLabel(day: decision.date, now: now)])
          .joined(separator: " · ")
        let result = Text(decision.result.label)
          .font(.geist(11.5, semibold: true, relativeTo: .caption))
          .foregroundColor(Palette.color(decision.result))
        Text("\(result) · \(rest)")
          .font(.geist(11.5, relativeTo: .caption))
          .foregroundStyle(Palette.ink2)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

private struct EmptyDecisionView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HemicycleLogo().frame(width: 36, height: 20)
        .padding(.bottom, 4)
      Text("Décisions de l'Assemblée")
        .font(.geist(14, semibold: true, relativeTo: .subheadline))
        .tracking(-0.14)
        .foregroundStyle(Palette.ink)
      Text("Ouvrez l'app pour charger la dernière décision.")
        .font(.geist(11.5, relativeTo: .caption))
        .foregroundStyle(Palette.ink2)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension WidgetDecision {
  static let sample = WidgetDecision(
    id: "exemple",
    result: .adopte,
    date: "2026-10-13",
    title: "Juges spécialisés pour les violences sexuelles et intrafamiliales",
    stage: "1re lecture",
    explanation:
      "Le texte prévoit une formation obligatoire pour les magistrats chargés des violences sexuelles et intrafamiliales.",
    count: VoteCount(pour: 503, contre: 0, abstentions: 67),
    voteMode: .scrutinPublic
  )

  /// Exemples de la galerie et de l'aperçu (le grand widget en montre trois).
  static let samples = [
    sample,
    WidgetDecision(
      id: "exemple-rejet", result: .rejete, date: "2026-10-08",
      title: "Réforme de l'espace Schengen et contrôles aux frontières",
      stage: "Résolution (sans valeur de loi)", explanation: nil,
      count: VoteCount(pour: 144, contre: 199, abstentions: 5), voteMode: .scrutinPublic),
    WidgetDecision(
      id: "exemple-main-levee", result: .adopte, date: "2026-10-07",
      title: "Approbation d'un accord d'échange d'informations fiscales",
      stage: "1re lecture à l'AN · à main levée", explanation: nil, voteMode: .mainLevee),
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
    .contentMarginsDisabled()
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
  // Dernière décision de plus de trois jours, vote solennel à venir (#56).
  DecisionEntry(
    date: UpcomingVote.instant("2026-10-21T08:00:00Z")!,
    decisions: WidgetDecision.samples,
    upcomingVotes: [
      UpcomingVote(
        id: "exemple-vote", startsAt: UpcomingVote.instant("2026-10-27T14:00:00Z")!,
        title: "Budget de la Sécurité sociale pour 2027")
    ]),
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
