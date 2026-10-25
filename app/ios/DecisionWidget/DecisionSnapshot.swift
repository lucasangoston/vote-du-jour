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
  /// Prochains votes solennels, du plus proche au plus lointain (#56). Absent
  /// d'un instantané antérieur : liste vide.
  let upcomingVotes: [UpcomingVote]

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

  private enum CodingKeys: String, CodingKey { case version, decisions, upcomingVotes }

  init(version: Int, decisions: [WidgetDecision], upcomingVotes: [UpcomingVote] = []) {
    self.version = version
    self.decisions = decisions
    self.upcomingVotes = upcomingVotes
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decode(Int.self, forKey: .version)
    // Une décision illisible (valeur inconnue ajoutée par une version plus
    // récente de l'app) est ignorée plutôt que de vider le widget.
    let items = try container.decode([FailableDecision].self, forKey: .decisions)
    decisions = items.compactMap(\.value)
    // Champ optionnel (#56) : absent, malformé ou vote illisible, ignoré.
    let votes =
      (try? container.decodeIfPresent([FailableUpcomingVote].self, forKey: .upcomingVotes))
    upcomingVotes = (votes ?? nil)?.compactMap(\.value) ?? []
  }
}

/// Vote solennel inscrit à l'ordre du jour (#56) : `{"id": "…", "startsAt":
/// "2026-10-27T14:00:00.000Z", "title": "…"}`.
struct UpcomingVote: Decodable, Equatable {
  let id: String
  /// Début de la séance.
  let startsAt: Date
  /// Titre court, prêt à afficher.
  let title: String

  init(id: String, startsAt: Date, title: String) {
    self.id = id
    self.startsAt = startsAt
    self.title = title
  }

  private enum CodingKeys: String, CodingKey { case id, startsAt, title }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    title = try c.decode(String.self, forKey: .title)
    guard let startsAt = Self.instant(try c.decode(String.self, forKey: .startsAt)),
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .startsAt, in: c, debugDescription: "vote à venir illisible")
    }
    self.startsAt = startsAt
  }

  /// Instant ISO 8601 (`2026-10-27T14:00:00.000Z`, millisecondes facultatives).
  static func instant(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
}

extension UpcomingVote {
  /// Au-delà de ce nombre de jours sans décision, les widgets annoncent le
  /// prochain vote solennel.
  static let staleAfterDays = 3

  private static let weekdays = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]
  /// Mois abrégés, de janvier à décembre.
  static let months = [
    "janv.", "févr.", "mars", "avr.", "mai", "juin",
    "juil.", "août", "sept.", "oct.", "nov.", "déc.",
  ]

  private static var paris: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
  }

  /// Jour de la séance, à Paris.
  private var day: DateComponents {
    Self.paris.dateComponents([.year, .month, .day, .weekday], from: startsAt)
  }

  /// « mar. 27 oct. » (« 1er » pour le premier du mois), en heure de Paris.
  var dayLabel: String { "\(weekdayLabel) \(dayOfMonthLabel) \(monthLabel)" }

  /// « mar. »
  var weekdayLabel: String { Self.weekdays[(day.weekday ?? 1) - 1] }

  /// « 27 » (« 1er »).
  var dayOfMonthLabel: String { day.day == 1 ? "1er" : String(day.day ?? 0) }

  /// « oct. »
  var monthLabel: String { Self.months[(day.month ?? 1) - 1] }

  /// Heure de la séance à Paris : « 15 h », « 21 h 30 ».
  var timeLabel: String {
    let time = Self.paris.dateComponents([.hour, .minute], from: startsAt)
    let minute = time.minute ?? 0
    return minute == 0
      ? "\(time.hour ?? 0) h" : "\(time.hour ?? 0) h \(String(format: "%02d", minute))"
  }

  /// « Vote · mar. 15 h », sous le jour des widgets (#78).
  var whenLabel: String { "Vote · \(weekdayLabel) \(timeLabel)" }

  /// Lecture d'écran : « Prochain vote solennel, mar. 3 nov. à 15 h. Budget de l'État 2027 ».
  var accessibilityLabel: String {
    "Prochain vote solennel, \(dayLabel) à \(timeLabel). \(title)"
  }

  /// Vote à annoncer à l'instant `now` : le premier de `votes` dont le jour
  /// (à Paris) n'est pas passé, si la dernière décision (`latestDecisionDay`,
  /// `AAAA-MM-JJ`) a plus de `staleAfterDays` jours ou s'il n'y en a pas.
  /// Jours comptés comme les dates relatives, dans le fuseau de `calendar`.
  static func shown(
    among votes: [UpcomingVote], latestDecisionDay: String?, now: Date,
    calendar: Calendar = .current
  ) -> UpcomingVote? {
    let today = calendar.dateComponents([.year, .month, .day], from: now)
    if let latest = latestDecisionDay.flatMap(dayComponents),
      let age = daysBetween(latest, today), age <= staleAfterDays
    {
      return nil
    }
    return votes.first { vote in (daysBetween(today, vote.day) ?? -1) >= 0 }
  }

  private static func dayComponents(_ day: String) -> DateComponents? {
    let parts = day.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, (1...12).contains(parts[1]) else { return nil }
    return DateComponents(year: parts[0], month: parts[1], day: parts[2])
  }

  /// Jours de calendrier de `from` à `to` (deux minuits UTC : pas de
  /// décalage d'heure d'été).
  private static func daysBetween(_ from: DateComponents, _ to: DateComponents) -> Int? {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    guard
      let start = utc.date(from: DateComponents(year: from.year, month: from.month, day: from.day)),
      let end = utc.date(from: DateComponents(year: to.year, month: to.month, day: to.day))
    else { return nil }
    return utc.dateComponents([.day], from: start, to: end).day
  }
}

private struct FailableUpcomingVote: Decodable {
  let value: UpcomingVote?

  init(from decoder: Decoder) throws {
    value = try? UpcomingVote(from: decoder)
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
  /// Arc dans l'ordre de l'hémicycle (#67), s'il est publié ; sinon l'arc se
  /// dessine par sens à partir de `count`.
  let arc: [HemicyclePart]?
  /// Vote de chaque place de l'hémicycle (#78), lu dans le fichier de détail ;
  /// absent (décision provisoire, à main levée, détail pas encore lu), les
  /// widgets dessinent l'arc.
  let seats: SeatVotes?

  init(
    id: String, result: Result, date: String, title: String, stage: String?,
    explanation: String?, count: VoteCount? = nil, voteMode: VoteMode? = nil,
    arc: [HemicyclePart]? = nil, seats: SeatVotes? = nil
  ) {
    self.id = id
    self.result = result
    self.date = date
    self.title = title
    self.stage = stage
    self.explanation = explanation
    self.count = count
    self.voteMode = voteMode
    self.arc = arc
    self.seats = seats
  }

  private enum CodingKeys: String, CodingKey {
    case id, result, date, title, stage, explanation, count, voteMode, arc, seats
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
    // Arc de l'hémicycle (#67) : un arc illisible est ignoré (arc par sens).
    let parts = (try? c.decodeIfPresent([ArcPartJSON].self, forKey: .arc)) ?? nil
    arc = HemicyclePart.parse(parts?.map(\.object))
    // Sièges de l'hémicycle (#78) : illisibles, ignorés (arc).
    seats = SeatVotes(encoded: (try? c.decodeIfPresent(String.self, forKey: .seats)) ?? nil)
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

  /// « 8 oct. » (« 1er » pour le premier du mois), sous le titre du widget
  /// moyen (#78).
  var shortDateLabel: String {
    let parts = date.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, (1...12).contains(parts[1]) else { return date }
    return "\(parts[2] == 1 ? "1er" : String(parts[2])) \(UpcomingVote.months[parts[1] - 1])"
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

  /// « Adopté » / « Rejeté ».
  var resultLabel: String { result == .adopte ? "Adopté" : "Rejeté" }

  /// Lecture d'écran du widget (#78) : résultat, titre, totaux, puis les
  /// mentions. « Adopté. Juges des violences sexuelles. 503 pour, 0 contre,
  /// 67 abstentions. »
  var accessibilityLabel: String {
    let totals: String? =
      isMainLevee
      ? "Vote à main levée"
      : count.map { "\($0.pour) pour, \($0.contre) contre, \($0.abstentions) abstentions" }
    let provisional = isProvisional ? "Décision provisoire" : nil
    return [resultLabel, title, totals, provisional].compactMap { $0 }
      .map { $0.hasSuffix(".") ? $0 : $0 + "." }
      .joined(separator: " ")
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

/// Tronçon de l'arc tel qu'il figure dans l'instantané, relu sans règle :
/// `HemicyclePart.parse` les applique.
private struct ArcPartJSON: Decodable {
  let object: [String: Any]

  private enum CodingKeys: String, CodingKey { case position, n }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    var object: [String: Any] = [:]
    if let position = try? c.decode(String.self, forKey: .position) {
      object["position"] = position
    }
    if let n = try? c.decode(Int.self, forKey: .n) { object["n"] = NSNumber(value: n) }
    self.object = object
  }
}
