import Foundation

/// Rafraîchissement autonome du widget : la timeline télécharge elle-même
/// `v1/latest.json`, le convertit en instantané (même format que
/// `lib/src/home_widget/widget_snapshot.dart`) et l'écrit dans le groupe d'apps.
/// En cas d'échec, l'instantané précédent est gardé : le widget affiche les
/// dernières données connues.
enum DecisionFetcher {
  /// URL publique compilée, si l'app n'en a pas partagé une autre
  /// (`--dart-define=DATA_BASE_URL`).
  static let defaultBaseURL = "https://pub-51ad28220f184398acec4e2b145afd20.r2.dev"

  /// Clé écrite par l'app (`lib/src/home_widget/widget_data_source.dart`).
  static let baseURLKey = "data_base_url"

  /// Un instantané plus récent n'est pas retéléchargé : l'app vient de l'écrire
  /// et de recharger la timeline.
  static let freshness: TimeInterval = 15 * 60

  static func indexURL(baseURL: String) -> URL? {
    var base = baseURL
    while base.hasSuffix("/") { base.removeLast() }
    return URL(string: "\(base)/v1/latest.json")
  }

  static func refreshIfNeeded(now: Date = .now) async {
    guard let defaults = UserDefaults(suiteName: DecisionSnapshot.appGroupId) else { return }
    if let savedAt = savedAt(of: defaults.string(forKey: DecisionSnapshot.storageKey)),
      now.timeIntervalSince(savedAt) >= 0, now.timeIntervalSince(savedAt) < freshness
    {
      return
    }
    let baseURL = defaults.string(forKey: baseURLKey).flatMap { $0.isEmpty ? nil : $0 }
    guard let url = indexURL(baseURL: baseURL ?? defaultBaseURL) else { return }
    let request = URLRequest(
      url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200,
        let snapshot = SnapshotConverter.snapshot(fromIndex: data, savedAt: now)
      else { return }
      defaults.set(snapshot, forKey: DecisionSnapshot.storageKey)
    } catch {
      // Hors ligne : on garde l'instantané précédent.
    }
  }

  private static func savedAt(of snapshot: String?) -> Date? {
    guard
      let data = snapshot?.data(using: .utf8),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let savedAt = root["savedAt"] as? String
    else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: savedAt) ?? ISO8601DateFormatter().date(from: savedAt)
  }
}

/// Conversion fidèle de l'index publié (contrat `vote_contract`, version 1) vers
/// l'instantané du widget, comme `WidgetSnapshot.fromIndex` côté Dart : les trois
/// décisions lisibles les plus récentes, titre = `shortTitle` sinon
/// `officialTitle` (avec majuscule initiale), étape = `stage`.
enum SnapshotConverter {
  private static let types: Set<String> = [
    "ensemble", "motion_de_censure", "declaration_gouvernement", "rejet_prealable",
    "premiere_partie_budget", "resolution", "autre",
  ]
  private static let statuses: Set<String> = ["provisoire", "confirmee"]
  private static let results: Set<String> = ["adopte", "rejete"]
  private static let voteModes: Set<String> = ["scrutin_public", "main_levee"]
  /// Mention du mode de vote (`lib/src/vote_mode_label.dart`).
  private static let mainLeveeLabel = "à main levée"

  /// Instantané JSON, ou `nil` si l'index est illisible ou d'une autre version.
  static func snapshot(fromIndex data: Data, savedAt: Date) -> String? {
    guard
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      root["schemaVersion"] as? Int == 1,
      let items = root["decisions"] as? [Any]
    else { return nil }
    let decisions = items.lazy.compactMap { ($0 as? [String: Any]).flatMap(convert) }.prefix(3)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let snapshot: [String: Any] = [
      "version": DecisionSnapshot.supportedVersion,
      "savedAt": formatter.string(from: savedAt),
      "decisions": Array(decisions),
    ]
    guard let json = try? JSONSerialization.data(withJSONObject: snapshot) else { return nil }
    return String(data: json, encoding: .utf8)
  }

  /// Mêmes règles que `DecisionSummary.tryFromJson` : une décision malformée est
  /// ignorée.
  private static func convert(_ d: [String: Any]) -> [String: Any]? {
    // `voteMode` absent : scrutin public (index antérieurs au ticket #8) ;
    // `numero` n'est exigé que pour un scrutin public (absent à main levée).
    let rawMode = d["voteMode"].flatMap { $0 is NSNull ? nil : $0 }
    let voteMode = rawMode == nil ? "scrutin_public" : rawMode as? String
    let numero = d["numero"].flatMap { $0 is NSNull ? nil : $0 }
    guard
      let voteMode, voteModes.contains(voteMode),
      numero == nil || numero is Int,
      numero != nil || voteMode != "scrutin_public",
      let id = d["id"] as? String,
      let type = d["type"] as? String, types.contains(type),
      let status = d["status"] as? String, statuses.contains(status),
      let result = d["result"] as? String, results.contains(result),
      let date = normalizedDay(d["date"]),
      let officialTitle = d["officialTitle"] as? String,
      d["sourceUrl"] is String
    else { return nil }
    let title = (optionalString(d["shortTitle"]) ?? officialTitle)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    var out: [String: Any] = [
      "id": id,
      "result": result,
      "date": date,
      "title": title.prefix(1).uppercased() + title.dropFirst(),
    ]
    // Même règle que `WidgetDecision.fromSummary` : la mention « à main levée »
    // s'ajoute à l'étape, que le widget affiche déjà.
    let stage = optionalString(d["stage"])
    if voteMode == "main_levee" {
      out["stage"] = stage.map { "\($0) · \(mainLeveeLabel)" }
        ?? mainLeveeLabel.prefix(1).uppercased() + mainLeveeLabel.dropFirst()
    } else if let stage {
      out["stage"] = stage
    }
    return out
  }

  private static func optionalString(_ value: Any?) -> String? {
    guard let s = value as? String,
      !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    return s
  }

  private static func normalizedDay(_ value: Any?) -> String? {
    guard let s = value as? String else { return nil }
    let parts = s.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else {
      return nil
    }
    return String(format: "%04d-%02d-%02d", parts[0], parts[1], parts[2])
  }
}
