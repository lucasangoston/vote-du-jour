import Foundation

/// Instantané écrit par l'app (`lib/src/home_widget/widget_snapshot.dart`) dans
/// les UserDefaults du groupe d'apps. Les champs optionnels absents ne sont pas
/// affichés.
struct DecisionSnapshot: Decodable {
  static let appGroupId = "group.com.lucasangoston.votedujour"
  static let storageKey = "decisions_snapshot"
  static let supportedVersion = 1

  let version: Int
  let decisions: [WidgetDecision]

  /// Lit l'instantané partagé ; `nil` si l'app ne l'a pas encore écrit ou s'il
  /// est d'une version inconnue.
  static func load() -> DecisionSnapshot? {
    guard
      let defaults = UserDefaults(suiteName: appGroupId),
      let json = defaults.string(forKey: storageKey),
      let data = json.data(using: .utf8),
      let snapshot = try? JSONDecoder().decode(DecisionSnapshot.self, from: data),
      snapshot.version == supportedVersion
    else { return nil }
    return snapshot
  }

  private enum CodingKeys: String, CodingKey { case version, decisions }

  init(version: Int, decisions: [WidgetDecision]) {
    self.version = version
    self.decisions = decisions
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decode(Int.self, forKey: .version)
    // Une décision illisible (valeur inconnue ajoutée par une version plus
    // récente de l'app) est ignorée plutôt que de vider le widget.
    let items = try container.decode([FailableDecision].self, forKey: .decisions)
    decisions = items.compactMap(\.value)
  }
}

struct WidgetDecision: Decodable {
  enum Result: String, Decodable { case adopte, rejete }

  let id: String
  let result: Result
  /// Jour du vote, au format `AAAA-MM-JJ`.
  let date: String
  let title: String
  let stage: String?
  let explanation: String?

  var day: Date? {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Europe/Paris")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: date)
  }

  /// « 13 octobre 2026 » (« 1er » pour le premier du mois).
  var dateLabel: String {
    guard let day else { return date }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "fr_FR")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "MMMM yyyy"
    let dayOfMonth = calendar.component(.day, from: day)
    return "\(dayOfMonth == 1 ? "1er" : String(dayOfMonth)) \(formatter.string(from: day))"
  }
}

private struct FailableDecision: Decodable {
  let value: WidgetDecision?

  init(from decoder: Decoder) throws {
    value = try? WidgetDecision(from: decoder)
  }
}
