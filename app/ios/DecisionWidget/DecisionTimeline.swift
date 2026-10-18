import WidgetKit

/// Timeline du widget : une entrée maintenant et une à minuit (la date relative
/// change), rechargée au bout d'une heure. WidgetKit peut espacer ces
/// rechargements selon son budget (de l'ordre de 40 à 70 par jour).
enum DecisionTimeline {
  static let reloadInterval: TimeInterval = 60 * 60

  static func make(now: Date = .now, calendar: Calendar = .current) async -> Timeline<DecisionEntry> {
    await DecisionFetcher.refreshIfNeeded(now: now)
    // Les jours sans séance, l'index publié garde les décisions précédentes :
    // le widget affiche toujours les dernières. Toutes les tailles partagent
    // cette timeline : le grand widget en affiche trois, les autres une.
    let decisions = DecisionSnapshot.load()?.latest(DecisionSnapshot.largeWidgetCount) ?? []
    var entries = [DecisionEntry(date: now, decisions: decisions)]
    if let midnight = calendar.nextDate(
      after: now, matching: DateComponents(hour: 0, minute: 0, second: 0),
      matchingPolicy: .nextTime)
    {
      entries.append(DecisionEntry(date: midnight, decisions: decisions))
    }
    return Timeline(entries: entries, policy: .after(now.addingTimeInterval(reloadInterval)))
  }
}
