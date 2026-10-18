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
  /// Décompte du scrutin public, s'il est connu (instantanés récents, #29).
  let count: VoteCount?
  /// Mode de vote, s'il est connu (instantanés récents, #29).
  let voteMode: VoteMode?

  init(
    id: String, result: Result, date: String, title: String, stage: String?,
    explanation: String?, count: VoteCount? = nil, voteMode: VoteMode? = nil
  ) {
    self.id = id
    self.result = result
    self.date = date
    self.title = title
    self.stage = stage
    self.explanation = explanation
    self.count = count
    self.voteMode = voteMode
  }

  private enum CodingKeys: String, CodingKey {
    case id, result, date, title, stage, explanation, count, voteMode
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    result = try c.decode(Result.self, forKey: .result)
    date = try c.decode(String.self, forKey: .date)
    title = try c.decode(String.self, forKey: .title)
    stage = try c.decodeIfPresent(String.self, forKey: .stage)
    explanation = try c.decodeIfPresent(String.self, forKey: .explanation)
    // Champs optionnels : une valeur illisible est ignorée, la décision reste
    // affichée (arc plein couleur du résultat).
    count = (try? c.decodeIfPresent(VoteCount.self, forKey: .count)) ?? nil
    voteMode =
      ((try? c.decodeIfPresent(String.self, forKey: .voteMode)) ?? nil).flatMap(VoteMode.init)
  }

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

/// Décompte d'un scrutin public : `{"pour":503,"contre":0,"abstentions":67}`.
/// Les autres clés (`nonVotants`) sont ignorées.
struct VoteCount: Decodable, Equatable {
  let pour: Int
  let contre: Int
  let abstentions: Int

  init(pour: Int, contre: Int, abstentions: Int) {
    self.pour = pour
    self.contre = contre
    self.abstentions = abstentions
  }

  private enum CodingKeys: String, CodingKey { case pour, contre, abstentions }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    pour = try c.decode(Int.self, forKey: .pour)
    contre = try c.decode(Int.self, forKey: .contre)
    abstentions = try c.decode(Int.self, forKey: .abstentions)
    guard pour >= 0, contre >= 0, abstentions >= 0 else {
      throw DecodingError.dataCorruptedError(
        forKey: .pour, in: c, debugDescription: "décompte négatif")
    }
  }

  /// Lit un décompte dans un objet issu de `JSONSerialization` ; `nil` s'il est
  /// absent ou malformé (valeur manquante, négative, non entière).
  init?(json: Any?) {
    guard let dict = json as? [String: Any] else { return nil }
    func number(_ key: String) -> Int? {
      guard let n = dict[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
        n.doubleValue == n.doubleValue.rounded(), n.intValue >= 0
      else { return nil }
      return n.intValue
    }
    guard let pour = number("pour"), let contre = number("contre"),
      let abstentions = number("abstentions")
    else { return nil }
    self.init(pour: pour, contre: contre, abstentions: abstentions)
  }

  /// Forme écrite dans l'instantané.
  var json: [String: Int] { ["pour": pour, "contre": contre, "abstentions": abstentions] }
}

enum VoteMode: String {
  case scrutinPublic = "scrutin_public"
  case mainLevee = "main_levee"
}

/// Mentions que l'instantané ajoute à l'étape (« 1re lecture à l'AN · à main
/// levée · provisoire », ou « À main levée » seule) : les widgets les placent
/// selon leur taille.
extension WidgetDecision {
  static let mainLeveeMention = "à main levée"
  static let provisionalMention = "provisoire"

  private var stageParts: [String] {
    (stage ?? "").components(separatedBy: " · ")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func isMention(_ part: String) -> Bool {
    let lower = part.lowercased()
    return lower == mainLeveeMention || lower == provisionalMention
  }

  /// Étape sans les mentions (« 1re lecture à l'AN »), si elle existe.
  var stageWithoutMentions: String? {
    let parts = stageParts.filter { !Self.isMention($0) }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  /// Vote à main levée : `voteMode`, ou la mention des anciens instantanés.
  var isMainLevee: Bool {
    voteMode == .mainLevee || stageParts.contains { $0.lowercased() == Self.mainLeveeMention }
  }

  var isProvisional: Bool {
    stageParts.contains { $0.lowercased() == Self.provisionalMention }
  }

  /// Mentions en minuscules : « à main levée » puis « provisoire ».
  var mentions: [String] {
    [isMainLevee ? Self.mainLeveeMention : nil, isProvisional ? Self.provisionalMention : nil]
      .compactMap { $0 }
  }
}

private struct FailableDecision: Decodable {
  let value: WidgetDecision?

  init(from decoder: Decoder) throws {
    value = try? WidgetDecision(from: decoder)
  }
}

extension DecisionSnapshot {
  /// Nombre de décisions affichées par le grand widget.
  static let largeWidgetCount = 3

  /// Les `count` décisions les plus récentes, de la plus récente à la plus
  /// ancienne (l'instantané est déjà dans cet ordre). Moins s'il en contient
  /// moins ; aucune pour un `count` négatif ou nul.
  func latest(_ count: Int) -> [WidgetDecision] {
    Array(decisions.prefix(max(0, count)))
  }
}
