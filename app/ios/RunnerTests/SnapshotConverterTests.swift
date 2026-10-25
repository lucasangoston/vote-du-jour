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

  func testTitreCourtDuResume() throws {
    let summary = #","summary":{"title":"Retour de l'âge légal à 62 ans","explanation":"e","promptVersion":2"#
    let long = String(repeating: "x", count: 36)
    let decisions = try convert([
      decision(8724, summary + #","shortTitle":"retraite à 62 ans"}"#),
      // Titre court trop long : repli sur le titre du résumé.
      decision(8723, summary + ",\"shortTitle\":\"\(long)\"}"),
    ])
    XCTAssertEqual(decisions[0]["title"] as? String, "Retraite à 62 ans")
    XCTAssertEqual(decisions[1]["title"] as? String, "Retour de l'âge légal à 62 ans")
  }

  func testDecompteEtModeDeVote() throws {
    let decisions = try convert([
      // `nonVotants` est ignoré.
      decision(8727, #","count":{"pour":503,"contre":0,"abstentions":67,"nonVotants":3}"#),
      // Index antérieur : ni décompte ni mode (scrutin public).
      decision(8726),
      // Décompte malformé : ignoré, la décision reste lisible.
      decision(8725, #","voteMode":"scrutin_public","count":{"pour":1,"contre":"2","abstentions":0}"#),
    ])
    XCTAssertEqual(decisions.count, 3)
    XCTAssertEqual(
      decisions[0]["count"] as? [String: Int], ["pour": 503, "contre": 0, "abstentions": 67])
    XCTAssertEqual(decisions[0]["voteMode"] as? String, "scrutin_public")
    XCTAssertNil(decisions[1]["count"])
    XCTAssertEqual(decisions[1]["voteMode"] as? String, "scrutin_public")
    XCTAssertNil(decisions[2]["count"])

    let mainLevee = try convert([
      """
      {"id":"L17-VD1","voteMode":"main_levee","type":"ensemble","result":"rejete",
      "date":"2026-10-07","officialTitle":"t","sourceUrl":"https://example.test/d"}
      """
    ])
    XCTAssertEqual(mainLevee[0]["voteMode"] as? String, "main_levee")
    XCTAssertNil(mainLevee[0]["count"])
  }

  /// L'instantané produit est relu par le widget avec son décompte.
  func testDecompteReluParLeWidget() throws {
    let index =
      #"{"schemaVersion":1,"decisions":["#
      + decision(8728, #","count":{"pour":144,"contre":199,"abstentions":5}"#) + "]}"
    let json = try XCTUnwrap(
      SnapshotConverter.snapshot(fromIndex: Data(index.utf8), savedAt: savedAt))
    let snapshot = try JSONDecoder().decode(DecisionSnapshot.self, from: Data(json.utf8))
    let widget = try XCTUnwrap(snapshot.decisions.first)
    XCTAssertEqual(widget.count, VoteCount(pour: 144, contre: 199, abstentions: 5))
    XCTAssertEqual(widget.voteMode, .scrutinPublic)
  }

  /// Arc dans l'ordre de l'hémicycle (#67) : recopié tel quel, relu par le
  /// widget ; un arc malformé est ignoré, la décision reste lisible.
  func testArcDeLHemicycle() throws {
    let arc8706 =
      #","count":{"pour":503,"contre":0,"abstentions":67},"arc":[{"position":"abstention","n":66},"#
      + #"{"position":"pour","n":382},{"position":"abstention","n":1},{"position":"pour","n":121}]"#
    let decisions = try convert([
      decision(8706, arc8706),
      // Sens inconnu (job plus récent) : tout l'arc est ignoré.
      decision(8705, #","arc":[{"position":"partage","n":3},{"position":"pour","n":2}]"#),
      // Nombre non entier, nul ou liste vide : ignoré.
      decision(8704, #","arc":[{"position":"pour","n":1.5}]"#),
    ])
    let arc = try XCTUnwrap(decisions[0]["arc"] as? [[String: Any]])
    XCTAssertEqual(arc.map { $0["position"] as? String }, ["abstention", "pour", "abstention", "pour"])
    XCTAssertEqual(arc.map { $0["n"] as? Int }, [66, 382, 1, 121])
    XCTAssertNil(decisions[1]["arc"])
    XCTAssertNil(decisions[2]["arc"])
    XCTAssertNil(try convert([decision(8703, #","arc":[{"position":"pour","n":0}]"#)])[0]["arc"])
    XCTAssertNil(try convert([decision(8702, #","arc":[]"#)])[0]["arc"])

    let index = #"{"schemaVersion":1,"decisions":["# + decision(8706, arc8706) + "]}"
    let json = try XCTUnwrap(
      SnapshotConverter.snapshot(fromIndex: Data(index.utf8), savedAt: savedAt))
    let snapshot = try JSONDecoder().decode(DecisionSnapshot.self, from: Data(json.utf8))
    let widget = try XCTUnwrap(snapshot.decisions.first)
    XCTAssertEqual(
      widget.arc,
      [
        HemicyclePart(.abstention, 66), HemicyclePart(.pour, 382), HemicyclePart(.abstention, 1),
        HemicyclePart(.pour, 121),
      ])
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

  // MARK: - Prochain vote solennel (#56)

  private func upcoming(
    _ id: String, kind: String = "vote_solennel", startsAt: String, shortTitle: String = "budget",
    extra: String = ""
  ) -> String {
    """
    {"id":"\(id)","kind":"\(kind)","startsAt":"\(startsAt)","seanceRef":"RUANS1",
    "label":"Vote solennel","shortTitle":"\(shortTitle)"\(extra)}
    """
  }

  private func snapshot(upcoming items: [String]?) throws -> String {
    let block = items.map { #","upcoming":["# + $0.joined(separator: ",") + "]" } ?? ""
    let index = #"{"schemaVersion":1,"decisions":["# + decision(8730) + "]" + block + "}"
    return try XCTUnwrap(
      SnapshotConverter.snapshot(fromIndex: Data(index.utf8), savedAt: savedAt))
  }

  func testVotesSolennelsAVenir() throws {
    let json = try snapshot(upcoming: [
      upcoming("PT3", startsAt: "2026-11-03T14:00:00Z", shortTitle: "budget 2027"),
      upcoming("PT1", kind: "discussion", startsAt: "2026-10-22T13:00:00Z"),
      upcoming(
        "PT2", startsAt: "2026-10-27T14:00:00.000Z",
        shortTitle: " Budget de la Sécurité sociale pour 2027 "),
      // Malformés : nature inconnue, date illisible, titre vide, séance absente.
      upcoming("PT4", kind: "question", startsAt: "2026-10-28T14:00:00Z"),
      upcoming("PT5", startsAt: "mardi"),
      upcoming("PT6", startsAt: "2026-10-28T14:00:00Z", shortTitle: " "),
      upcoming("PT7", startsAt: "2026-10-28T14:00:00Z").replacingOccurrences(
        of: #""seanceRef":"RUANS1","#, with: ""),
    ])
    let root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let votes = try XCTUnwrap(root["upcomingVotes"] as? [[String: String]])
    XCTAssertEqual(
      votes,
      [
        [
          "id": "PT2", "startsAt": "2026-10-27T14:00:00.000Z",
          "title": "Budget de la Sécurité sociale pour 2027",
        ],
        ["id": "PT3", "startsAt": "2026-11-03T14:00:00.000Z", "title": "Budget 2027"],
      ])
    // Le widget relit l'instantané produit.
    let read = try JSONDecoder().decode(DecisionSnapshot.self, from: Data(json.utf8))
    XCTAssertEqual(read.upcomingVotes.map(\.id), ["PT2", "PT3"])
    XCTAssertEqual(read.decisions.count, 1)
  }

  func testSansVoteSolennelChampOmis() throws {
    for items in [nil, [], [upcoming("PT1", kind: "discussion", startsAt: "2026-10-22T13:00:00Z")]]
    {
      let root = try XCTUnwrap(
        JSONSerialization.jsonObject(with: Data(try snapshot(upcoming: items).utf8))
          as? [String: Any])
      XCTAssertNil(root["upcomingVotes"])
    }
  }

  func testAncienInstantaneEtVotesIllisibles() throws {
    let old = #"{"version":1,"savedAt":"2026-10-17T00:00:00.000Z","decisions":[]}"#
    XCTAssertEqual(
      try JSONDecoder().decode(DecisionSnapshot.self, from: Data(old.utf8)).upcomingVotes, [])
    let mixed = """
      {"version":1,"savedAt":"2026-10-17T00:00:00.000Z","decisions":[],"upcomingVotes":[
      {"id":"a","startsAt":"demain","title":"t"},{"id":"b","startsAt":"2026-10-27T14:00:00Z","title":" "},
      {"id":"c","startsAt":"2026-10-27T15:00:00+01:00","title":"t"},"d"]}
      """
    let read = try JSONDecoder().decode(DecisionSnapshot.self, from: Data(mixed.utf8))
    XCTAssertEqual(read.upcomingVotes.map(\.id), ["c"])
    let invalid = #"{"version":1,"savedAt":"x","decisions":[],"upcomingVotes":"aucun"}"#
    XCTAssertEqual(
      try JSONDecoder().decode(DecisionSnapshot.self, from: Data(invalid.utf8)).upcomingVotes, [])
  }

  private var paris: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
  }

  private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    paris.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
  }

  func testLibelleDuJourAParis() {
    let plfss = UpcomingVote(id: "a", startsAt: at(2026, 10, 27, 15), title: "t")
    XCTAssertEqual(plfss.dayLabel, "mar. 27 oct.")
    // 23 h 30 UTC le 30 novembre : déjà le 1er décembre à Paris.
    let late = UpcomingVote(
      id: "b", startsAt: UpcomingVote.instant("2026-11-30T23:30:00Z")!, title: "t")
    XCTAssertEqual(late.dayLabel, "mar. 1er déc.")
  }

  func testAnnonceSeulementSansDecisionRecente() {
    let votes = [
      UpcomingVote(id: "passe", startsAt: at(2026, 10, 20, 15), title: "t"),
      UpcomingVote(id: "plfss", startsAt: at(2026, 10, 27, 15), title: "t"),
    ]
    func shown(_ latest: String?, _ now: Date) -> String? {
      UpcomingVote.shown(among: votes, latestDecisionDay: latest, now: now, calendar: paris)?.id
    }
    // Dernière décision le 17 : trois jours le 20, quatre le 21.
    XCTAssertNil(shown("2026-10-17", at(2026, 10, 20, 23)))
    XCTAssertEqual(shown("2026-10-17", at(2026, 10, 21, 0)), "plfss")
    XCTAssertEqual(shown(nil, at(2026, 10, 21)), "plfss")
    // Le jour du vote, il est encore annoncé ; le lendemain, plus rien.
    XCTAssertEqual(shown("2026-10-13", at(2026, 10, 20, 23)), "passe")
    XCTAssertEqual(shown("2026-10-17", at(2026, 10, 27, 23)), "plfss")
    XCTAssertNil(shown("2026-10-17", at(2026, 10, 28, 0)))
    XCTAssertNil(UpcomingVote.shown(among: [], latestDecisionDay: nil, now: .now))
  }

  func testAutreVersionOuIllisible() {
    XCTAssertNil(
      SnapshotConverter.snapshot(
        fromIndex: Data(#"{"schemaVersion":2,"decisions":[]}"#.utf8), savedAt: savedAt))
    XCTAssertNil(SnapshotConverter.snapshot(fromIndex: Data("pas du json".utf8), savedAt: savedAt))
  }

  func testSiegesDeLaDerniereDecision() throws {
    let index = Data(
      (#"{"schemaVersion":1,"decisions":["# + decision(8714).replacingOccurrences(
        of: #""ensemble""#, with: #""inconnu""#) + "," + decision(8713) + "," + decision(8712)
        + "]}").utf8)
    // La première décision lisible, celle que les widgets dessinent.
    XCTAssertEqual(SnapshotConverter.latestDecisionId(fromIndex: index), "VTANR5L17V8713")
    XCTAssertNil(SnapshotConverter.latestDecisionId(fromIndex: Data("{}".utf8)))
    let votes = try XCTUnwrap(SeatVotes(encoded: "pc-a"))
    let json = try XCTUnwrap(
      SnapshotConverter.snapshot(
        fromIndex: index, savedAt: savedAt, seats: ["VTANR5L17V8713": votes]))
    let snapshot = try JSONDecoder().decode(DecisionSnapshot.self, from: Data(json.utf8))
    XCTAssertEqual(snapshot.decisions.map(\.id), ["VTANR5L17V8713", "VTANR5L17V8712"])
    XCTAssertEqual(snapshot.decisions[0].seats, votes)
    XCTAssertNil(snapshot.decisions[1].seats)
  }

  func testSiegesIllisiblesDansLInstantane() throws {
    let json = #"""
      {"version":1,"decisions":[{"id":"a","result":"adopte","date":"2026-10-13","title":"T",
      "seats":"ppz"}]}
      """#
    let snapshot = try JSONDecoder().decode(DecisionSnapshot.self, from: Data(json.utf8))
    XCTAssertEqual(snapshot.decisions.count, 1)
    XCTAssertNil(snapshot.decisions[0].seats)
  }

  func testURLDuDetail() {
    XCTAssertEqual(
      DecisionFetcher.detailURL(baseURL: "https://exemple.test/", id: "VTANR5L17V8706")?
        .absoluteString,
      "https://exemple.test/v1/decisions/VTANR5L17V8706.json")
  }
}
