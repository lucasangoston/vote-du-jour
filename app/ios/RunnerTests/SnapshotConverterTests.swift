import XCTest

/// Tests de la conversion `latest.json` → instantané du widget
/// (`DecisionWidget/DecisionFetcher.swift`, compilé aussi dans cette cible).
final class SnapshotConverterTests: XCTestCase {
  private let savedAt = Date(timeIntervalSince1970: 1_792_236_600)  // 2026-10-17T11:30:00Z

  private func decision(_ numero: Int, _ extra: String = "") -> String {
    """
    {"id":"VTANR5L17V\(numero)","numero":\(numero),"type":"ensemble","status":"confirmee",
    "result":"adopte","date":"2026-10-1\(numero % 10)",
    "officialTitle":"l'ensemble du projet de loi n° \(numero).",
    "sourceUrl":"https://www.assemblee-nationale.fr/dyn/17/scrutins/\(numero)"\(extra)}
    """
  }

  private func convert(_ decisions: [String]) throws -> [[String: Any]] {
    let index = #"{"schemaVersion":1,"decisions":["# + decisions.joined(separator: ",") + "]}"
    let json = try XCTUnwrap(
      SnapshotConverter.snapshot(fromIndex: Data(index.utf8), savedAt: savedAt))
    // Le widget relit l'instantané produit.
    let snapshot = try JSONDecoder().decode(DecisionSnapshot.self, from: Data(json.utf8))
    XCTAssertEqual(snapshot.version, 1)
    let root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    return try XCTUnwrap(root["decisions"] as? [[String: Any]])
  }

  func testTroisPremieresDecisionsLisibles() throws {
    let decisions = try convert([
      decision(8715, #","shortTitle":"budget 2027","stage":"1re lecture à l'AN""#),
      decision(8714).replacingOccurrences(of: #""ensemble""#, with: #""inconnu""#),
      decision(8713, #","shortTitle":"  ","stage":"""#),
      decision(8712),
      decision(8711),
    ])
    XCTAssertEqual(decisions.map { $0["id"] as? String }, ["VTANR5L17V8715", "VTANR5L17V8713", "VTANR5L17V8712"])
    XCTAssertEqual(decisions[0]["title"] as? String, "Budget 2027")
    XCTAssertEqual(decisions[0]["stage"] as? String, "1re lecture à l'AN")
    XCTAssertEqual(decisions[0]["date"] as? String, "2026-10-15")
    XCTAssertEqual(decisions[1]["title"] as? String, "L'ensemble du projet de loi n° 8713.")
    XCTAssertNil(decisions[1]["stage"])
  }

  func testMainLeveeSansNumero() throws {
    let mainLevee = """
      {"id":"L17-VD234087DEC","voteMode":"main_levee","type":"ensemble","status":"confirmee",
      "result":"adopte","date":"2026-10-07","officialTitle":"projet de loi GloBE",
      "sourceUrl":"https://example.test/d"
      """
    let decisions = try convert([
      mainLevee + #","stage":"1re lecture à l'AN"}"#,
      mainLevee + "}",
      decision(8717).replacingOccurrences(of: #""numero":8717,"#, with: ""),
      decision(8718).replacingOccurrences(
        of: #""ensemble","#, with: #""ensemble","voteMode":"inconnu","#),
      decision(8719, #","voteMode":"scrutin_public""#),
    ])
    XCTAssertEqual(decisions.count, 3)
    XCTAssertEqual(decisions[0]["stage"] as? String, "1re lecture à l'AN · à main levée")
    XCTAssertEqual(decisions[0]["title"] as? String, "Projet de loi GloBE")
    XCTAssertEqual(decisions[1]["stage"] as? String, "À main levée")
    XCTAssertEqual(decisions[2]["id"] as? String, "VTANR5L17V8719")
  }

  func testProvisoireDansLEtape() throws {
    let decisions = try convert([
      decision(8721, #","stage":"1re lecture à l'AN""#)
        .replacingOccurrences(of: #""confirmee""#, with: #""provisoire""#),
      decision(8720).replacingOccurrences(of: #""confirmee""#, with: #""provisoire""#),
      // `status` absent : confirmée.
      decision(8719, #","stage":"1re lecture à l'AN""#)
        .replacingOccurrences(of: #""status":"confirmee","#, with: ""),
      decision(8718).replacingOccurrences(of: #""confirmee""#, with: #""annulee""#),
    ])
    XCTAssertEqual(decisions.count, 3)
    XCTAssertEqual(decisions[0]["stage"] as? String, "1re lecture à l'AN · provisoire")
    XCTAssertEqual(decisions[0]["title"] as? String, "L'ensemble du projet de loi n° 8721.")
    XCTAssertEqual(decisions[1]["stage"] as? String, "Provisoire")
    XCTAssertEqual(decisions[2]["stage"] as? String, "1re lecture à l'AN")
  }

  func testResumeTitreEtExplication() throws {
    let summary =
      #","summary":{"title":"retraite à 62 ans","explanation":" Le texte prévoit… ","promptVersion":1}"#
    let decisions = try convert([
      decision(8724, #","shortTitle":"budget""# + summary),
      // Résumé malformé (pas de version) : ignoré, la décision reste lisible.
      decision(8723, #","shortTitle":"budget","summary":{"title":"x","explanation":"y"}"#),
      decision(8722),
    ])
    XCTAssertEqual(decisions.count, 3)
    XCTAssertEqual(decisions[0]["title"] as? String, "Retraite à 62 ans")
    XCTAssertEqual(decisions[0]["explanation"] as? String, "Le texte prévoit…")
    XCTAssertEqual(decisions[1]["title"] as? String, "Budget")
    XCTAssertNil(decisions[1]["explanation"])
    XCTAssertNil(decisions[2]["explanation"])
  }

  /// Téléchargement réel de `latest.json` vers le groupe d'apps, comme le fait
  /// la timeline. Réseau requis : lancé seulement avec
  /// `TEST_RUNNER_VDJ_NETWORK_TESTS=1 xcodebuild test …`.
  func testTelechargementReelVersLeGroupeDApps() async throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["VDJ_NETWORK_TESTS"] == "1", "test réseau désactivé")
    let defaults = try XCTUnwrap(UserDefaults(suiteName: DecisionSnapshot.appGroupId))
    defaults.removeObject(forKey: DecisionSnapshot.storageKey)
    defaults.removeObject(forKey: DecisionFetcher.baseURLKey)

    await DecisionFetcher.refreshIfNeeded()

    let snapshot = try XCTUnwrap(DecisionSnapshot.load())
    XCTAssertFalse(snapshot.decisions.isEmpty)
    print("Instantané téléchargé : \(snapshot.decisions.map(\.title))")
  }

  func testAutreVersionOuIllisible() {
    XCTAssertNil(
      SnapshotConverter.snapshot(
        fromIndex: Data(#"{"schemaVersion":2,"decisions":[]}"#.utf8), savedAt: savedAt))
    XCTAssertNil(SnapshotConverter.snapshot(fromIndex: Data("pas du json".utf8), savedAt: savedAt))
  }
}
