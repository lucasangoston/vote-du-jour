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
  /// Dernières décisions, de la plus récente à la plus ancienne ; les widgets
  /// n'affichent que la première (#78).
  let decisions: [WidgetDecision]
  /// Prochains votes solennels de l'instantané (#56).
  var upcomingVotes: [UpcomingVote] = []

  var decision: WidgetDecision? { decisions.first }

  /// Vote solennel annoncé à la place de la décision (petit et moyen) : la
  /// dernière décision a plus de trois jours (ou il n'y en a pas) et le vote
  /// n'est pas passé.
  var upcomingVote: UpcomingVote? {
    UpcomingVote.shown(among: upcomingVotes, latestDecisionDay: decision?.date, now: date)
  }

  /// Prochain vote pas encore passé, dans la bande du grand widget.
  var nextVote: UpcomingVote? {
    UpcomingVote.shown(among: upcomingVotes, latestDecisionDay: nil, now: date)
  }
}

struct DecisionProvider: TimelineProvider {
  func placeholder(in context: Context) -> DecisionEntry {
    DecisionEntry(date: .now, decisions: WidgetDecision.samples, upcomingVotes: UpcomingVote.samples)
  }

  func getSnapshot(in context: Context, completion: @escaping (DecisionEntry) -> Void) {
    // Dans la galerie, montrer un exemple si l'app n'a encore rien écrit.
    let snapshot = DecisionSnapshot.load()
    let decisions = snapshot?.latest(DecisionSnapshot.largeWidgetCount) ?? []
    let sample = decisions.isEmpty && context.isPreview
    completion(
      DecisionEntry(
        date: .now,
        decisions: sample ? WidgetDecision.samples : decisions,
        upcomingVotes: sample ? UpcomingVote.samples : snapshot?.upcomingVotes ?? []))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<DecisionEntry>) -> Void) {
    // Rafraîchi sans l'app toutes les heures, avec une entrée à minuit (voir
    // DecisionFetcher.swift). L'app recharge aussi le widget dès qu'elle écrit
    // un nouvel instantané.
    Task { completion(await DecisionTimeline.make()) }
  }
}

struct DecisionWidgetView: View {
  let entry: DecisionEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .widgetURL(url)
      .containerBackground(for: .widget) { Palette.surface }
  }

  @ViewBuilder
  private var content: some View {
    // Sans décision récente, le petit et le moyen widget annoncent le
    // prochain vote solennel ; le grand le met dans sa bande du bas.
    switch (family, entry.decision, entry.upcomingVote) {
    case (.systemSmall, _, let vote?):
      SmallUpcomingView(vote: vote).padding(14)
    case (.systemMedium, _, let vote?):
      MediumUpcomingView(vote: vote).padding(14)
    case (_, nil, _):
      EmptyDecisionView().padding(14)
    case (.systemSmall, let decision?, _):
      SmallDecisionView(decision: decision).padding(14)
    case (.systemLarge, let decision?, _):
      LargeDecisionView(decision: decision, nextVote: entry.nextVote)
    case (_, let decision?, _):
      MediumDecisionView(decision: decision).padding(14)
    }
  }

  /// Le détail de la décision affichée, ou la liste quand le widget annonce
  /// le prochain vote (la bande du grand widget a son propre lien).
  private var url: URL {
    if family != .systemLarge, entry.upcomingVote != nil { return listURL }
    return entry.decision?.detailURL ?? listURL
  }
}

/// Mot du résultat, couleur du vote gagnant, suivi des mentions
/// (« provisoire », « à main levée ») en petit. Sous un décompte
/// (`withCount`), « à main levée » y est déjà.
private struct ResultLine: View {
  let decision: WidgetDecision
  var size: CGFloat = WidgetTheme.resultSize
  var withCount = false

  private var mentions: [String] {
    decision.mentions.filter { !(withCount && $0 == WidgetDecision.mainLeveeMention) }
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(decision.resultLabel)
        .font(WidgetTheme.display(size))
        .tracking(-0.01 * size)
        .foregroundStyle(Palette.color(decision.result))
        .fixedSize()
      if !mentions.isEmpty {
        Text(mentions.joined(separator: " · "))
          .font(WidgetTheme.meta(11.5))
          .foregroundStyle(Palette.ink2)
          .lineLimit(1)
          .minimumScaleFactor(WidgetTheme.minimumScale)
      }
    }
  }
}

/// Titre court : nombre de lignes maximal et léger rétrécissement aux
/// grandes tailles de texte.
private struct ShortTitle: View {
  let text: String
  let font: Font
  var lineLimit = 2

  var body: some View {
    Text(text)
      .font(font)
      .foregroundStyle(Palette.ink)
      .lineLimit(lineLimit)
      .minimumScaleFactor(WidgetTheme.minimumScale)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// Décompte sous l'hémicycle, ou « À main levée » sans scrutin public.
private struct CountLine: View {
  let decision: WidgetDecision

  var body: some View {
    if decision.isMainLevee {
      Text("À main levée")
        .font(WidgetTheme.meta())
        .foregroundStyle(Palette.ink2)
        .lineLimit(1)
    } else if let count = decision.count {
      TallyView(count: count)
    }
  }
}

/// Petit widget : hémicycle, « Adopté » / « Rejeté », titre court sur deux
/// lignes.
private struct SmallDecisionView: View {
  let decision: WidgetDecision

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      DecisionHemicycleView(decision: decision)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      ResultLine(decision: decision)
        .padding(.top, 8)
        .layoutPriority(1)
      ShortTitle(text: decision.title, font: WidgetTheme.title(WidgetTheme.smallTitleSize))
        .padding(.top, 2)
        .layoutPriority(1)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(decision.accessibilityLabel)
  }
}

/// Moyen : hémicycle et décompte à gauche ; résultat, titre court et date à
/// droite.
private struct MediumDecisionView: View {
  let decision: WidgetDecision

  var body: some View {
    GeometryReader { proxy in
      HStack(alignment: .center, spacing: 14) {
        VStack(spacing: 8) {
          DecisionHemicycleView(decision: decision, arcLineWidth: 14)
          CountLine(decision: decision)
        }
        .frame(width: proxy.size.width * 0.46)
        VStack(alignment: .leading, spacing: 0) {
          ResultLine(decision: decision, withCount: true)
          ShortTitle(
            text: decision.title, font: WidgetTheme.display(WidgetTheme.mediumTitleSize),
            lineLimit: 3
          )
          .padding(.top, 4)
          Spacer(minLength: 4)
          Text(decision.shortDateLabel)
            .font(WidgetTheme.meta())
            .foregroundStyle(Palette.ink2)
            .lineLimit(1)
        }
        .frame(maxHeight: .infinity, alignment: .top)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(decision.accessibilityLabel)
  }
}

/// Grand : la dernière décision en grand (hémicycle, résultat, décompte, titre
/// court), puis la bande du prochain vote, qui ouvre la liste.
private struct LargeDecisionView: View {
  let decision: WidgetDecision
  let nextVote: UpcomingVote?

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 0) {
        DecisionHemicycleView(decision: decision)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        HStack(alignment: .firstTextBaseline) {
          ResultLine(decision: decision, size: WidgetTheme.largeResultSize, withCount: true)
          Spacer(minLength: 8)
          CountLine(decision: decision)
        }
        .padding(.top, 10)
        .layoutPriority(1)
        ShortTitle(text: decision.title, font: WidgetTheme.display(WidgetTheme.largeTitleSize))
          .padding(.top, 6)
          .layoutPriority(1)
      }
      .padding(.horizontal, 18)
      .padding(.top, 18)
      .padding(.bottom, nextVote == nil ? 18 : 12)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(decision.accessibilityLabel)
      if let nextVote {
        Link(destination: listURL) { NextVoteBand(vote: nextVote) }
          .layoutPriority(1)
      }
    }
  }
}

/// Bande « prochain vote » du grand widget : le jour et le mois, le titre
/// court et « Vote · mar. 15 h ».
private struct NextVoteBand: View {
  let vote: UpcomingVote

  var body: some View {
    HStack(spacing: 14) {
      VStack(spacing: 0) {
        Text(vote.dayOfMonthLabel)
          .font(WidgetTheme.day(WidgetTheme.bandDaySize))
          .foregroundStyle(Palette.ink)
        Text(vote.monthLabel)
          .font(WidgetTheme.meta(WidgetTheme.monthSize))
          .foregroundStyle(Palette.ink2)
      }
      .lineLimit(1)
      .frame(minWidth: 40)
      VStack(alignment: .leading, spacing: 0) {
        Text(vote.title)
          .font(WidgetTheme.title(15, semibold: true))
          .foregroundStyle(Palette.ink)
          .lineLimit(1)
          .minimumScaleFactor(WidgetTheme.minimumScale)
        Text(vote.whenLabel)
          .font(WidgetTheme.meta())
          .foregroundStyle(Palette.ink2)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, 18)
    .padding(.top, 12)
    .padding(.bottom, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Palette.raised)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(vote.accessibilityLabel)
  }
}

/// Arc vide et jour du vote en grand, le mois dessous.
private struct UpcomingFigure: View {
  let vote: UpcomingVote

  var body: some View {
    EmptyArcView()
      .overlay(alignment: .bottom) {
        VStack(spacing: 0) {
          Text(vote.dayOfMonthLabel)
            .font(WidgetTheme.day(WidgetTheme.daySize))
            .foregroundStyle(Palette.ink)
            .minimumScaleFactor(0.6)
          Text(vote.monthLabel)
            .font(WidgetTheme.meta(WidgetTheme.monthSize))
            .foregroundStyle(Palette.ink2)
        }
        .lineLimit(1)
        .offset(y: 4)
      }
  }
}

/// Petit « prochain vote » : arc vide, jour en grand et mois, « Vote · mar.
/// 15 h », titre court.
private struct SmallUpcomingView: View {
  let vote: UpcomingVote

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      UpcomingFigure(vote: vote)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      Text(vote.whenLabel)
        .font(WidgetTheme.meta())
        .foregroundStyle(Palette.ink2)
        .lineLimit(1)
        .padding(.top, 8)
        .layoutPriority(1)
      ShortTitle(text: vote.title, font: WidgetTheme.title(WidgetTheme.smallTitleSize))
        .padding(.top, 2)
        .layoutPriority(1)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(vote.accessibilityLabel)
  }
}

/// Moyen « prochain vote » : l'arc vide et le jour à gauche, à la place de
/// l'hémicycle ; « Vote · mar. 15 h » et le titre court à droite.
private struct MediumUpcomingView: View {
  let vote: UpcomingVote

  var body: some View {
    GeometryReader { proxy in
      HStack(alignment: .center, spacing: 14) {
        UpcomingFigure(vote: vote).frame(width: proxy.size.width * 0.46)
        VStack(alignment: .leading, spacing: 4) {
          Text(vote.whenLabel)
            .font(WidgetTheme.meta())
            .foregroundStyle(Palette.ink2)
            .lineLimit(1)
          ShortTitle(
            text: vote.title, font: WidgetTheme.display(WidgetTheme.mediumTitleSize), lineLimit: 3)
        }
      }
      .frame(maxHeight: .infinity)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(vote.accessibilityLabel)
  }
}

private struct EmptyDecisionView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HemicycleLogo().frame(width: 36, height: 20)
        .padding(.bottom, 4)
      Text("Décisions de l'Assemblée")
        .font(WidgetTheme.title(WidgetTheme.smallTitleSize, semibold: true))
        .foregroundStyle(Palette.ink)
      Text("Ouvrez l'app pour charger la dernière décision.")
        .font(WidgetTheme.meta(11.5))
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
    title: "Juges des violences sexuelles",
    stage: "1re lecture",
    explanation:
      "Le texte prévoit une formation obligatoire pour les magistrats chargés des violences sexuelles et intrafamiliales.",
    count: VoteCount(pour: 503, contre: 0, abstentions: 67),
    voteMode: .scrutinPublic,
    seats: SeatVotes(encoded: HemicycleGeometry.sampleVotes)
  )

  /// Exemples des aperçus (le premier dans la galerie).
  static let samples = [
    sample,
    WidgetDecision(
      id: "exemple-rejet", result: .rejete, date: "2026-10-08",
      title: "Contrôles aux frontières Schengen",
      stage: "Résolution (sans valeur de loi)", explanation: nil,
      count: VoteCount(pour: 144, contre: 199, abstentions: 5), voteMode: .scrutinPublic),
    WidgetDecision(
      id: "exemple-main-levee", result: .adopte, date: "2026-10-07",
      title: "Accord d'échange fiscal",
      stage: "1re lecture à l'AN · à main levée", explanation: nil, voteMode: .mainLevee),
  ]
}

extension UpcomingVote {
  /// Exemple de la galerie (bande du grand widget).
  static let samples = [
    UpcomingVote(
      id: "exemple-vote", startsAt: UpcomingVote.instant("2026-11-03T14:00:00Z")!,
      title: "Budget de l'État 2027")
  ]
}

struct DecisionWidget: Widget {
  let kind = "DecisionWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: DecisionProvider()) { entry in
      DecisionWidgetView(entry: entry)
    }
    .configurationDisplayName("Dernière décision")
    .description("La dernière décision de l'Assemblée nationale, son hémicycle et le prochain vote.")
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
  DecisionEntry(
    date: UpcomingVote.instant("2026-10-14T08:00:00Z")!, decisions: WidgetDecision.samples,
    upcomingVotes: UpcomingVote.samples),
  // Sans sièges : l'arc du vote.
  DecisionEntry(date: .now, decisions: Array(WidgetDecision.samples.dropFirst())),
  DecisionEntry(date: .now, decisions: []),
  // Dernière décision de plus de trois jours, vote solennel à venir (#56).
  DecisionEntry(
    date: UpcomingVote.instant("2026-10-30T08:00:00Z")!,
    decisions: WidgetDecision.samples, upcomingVotes: UpcomingVote.samples),
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
