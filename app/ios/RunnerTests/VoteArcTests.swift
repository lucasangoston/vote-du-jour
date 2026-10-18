import XCTest

/// Tests de l'arc du vote (`DecisionWidget/VoteArc.swift`) et des champs de
/// l'instantané qui le pilotent (`count`, `voteMode`, mentions de l'étape).
final class VoteArcTests: XCTestCase {
  private typealias Segment = VoteArc.Segment

  private func arc(
    _ result: WidgetDecision.Result, _ count: VoteCount?, mainLevee: Bool = false
  ) -> VoteArc {
    VoteArc(result: result, count: count, mainLevee: mainLevee)
  }

  private func assertSegments(
    _ arc: VoteArc, _ expected: [(VoteArc.Tint, Double, Double)], file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard case .segments(let segments) = arc else {
      return XCTFail("arc \(arc) au lieu de tronçons", file: file, line: line)
    }
    XCTAssertEqual(segments.map(\.tint), expected.map(\.0), file: file, line: line)
    for (segment, (_, from, to)) in zip(segments, expected) {
      XCTAssertEqual(segment.from, from, accuracy: 0.0005, file: file, line: line)
      XCTAssertEqual(segment.to, to, accuracy: 0.0005, file: file, line: line)
    }
  }

  func testPourPuisAbstentionsPuisContre() {
    // Maquette : 144 pour, 199 contre, 5 abstentions → 41,4 % puis 1,4 %.
    assertSegments(
      arc(.rejete, VoteCount(pour: 144, contre: 199, abstentions: 5)),
      [(.pour, 0, 0.4138), (.abstention, 0.4138, 0.4282), (.contre, 0.4282, 1)])
  }

  func testTronconsVidesOmis() {
    // Maquette : 503 pour, 0 contre, 67 abstentions → 88,2 % de vert.
    assertSegments(
      arc(.adopte, VoteCount(pour: 503, contre: 0, abstentions: 67)),
      [(.pour, 0, 0.8825), (.abstention, 0.8825, 1)])
    assertSegments(arc(.rejete, VoteCount(pour: 0, contre: 12, abstentions: 0)), [(.contre, 0, 1)])
  }

  func testLeDernierTronconFermeLArc() {
    guard case .segments(let segments) = arc(.adopte, VoteCount(pour: 1, contre: 1, abstentions: 1))
    else { return XCTFail() }
    XCTAssertEqual(segments.last?.to, 1)
    XCTAssertEqual(segments.first?.from, 0)
    for (a, b) in zip(segments, segments.dropFirst()) { XCTAssertEqual(a.to, b.from) }
  }

  func testSansDecompteArcPleinCouleurDuResultat() {
    XCTAssertEqual(arc(.adopte, nil), .solid(.pour))
    XCTAssertEqual(arc(.rejete, nil), .solid(.contre))
    // Décompte nul : rien à répartir.
    XCTAssertEqual(arc(.rejete, VoteCount(pour: 0, contre: 0, abstentions: 0)), .solid(.contre))
  }

  func testMainLeveePointillesCouleurDuResultat() {
    XCTAssertEqual(arc(.adopte, nil, mainLevee: true), .dotted(.pour))
    XCTAssertEqual(arc(.rejete, nil, mainLevee: true), .dotted(.contre))
  }

  func testDecisionMainLeveeParVoteModeOuParMention() {
    let parMode = WidgetDecision(
      id: "a", result: .adopte, date: "2026-10-07", title: "t", stage: "1re lecture",
      explanation: nil, voteMode: .mainLevee)
    XCTAssertEqual(VoteArc(decision: parMode), .dotted(.pour))
    // Ancien instantané : seulement la mention dans l'étape.
    let parMention = WidgetDecision(
      id: "b", result: .rejete, date: "2026-10-07", title: "t", stage: "À main levée",
      explanation: nil)
    XCTAssertEqual(VoteArc(decision: parMention), .dotted(.contre))
  }

  func testPointsSymetriques() {
    // Arc du vote à main levée : 9 points (maquette, tous les 19,6 sur π × 50).
    let dots = VoteArc.dotPositions(length: .pi * 50, spacing: 19.6)
    XCTAssertEqual(dots.count, 9)
    XCTAssertEqual(dots.first, 0)
    XCTAssertEqual(dots.last, 1)
    // Icône : rangées de 15 et 11 sièges.
    XCTAssertEqual(VoteArc.dotPositions(length: .pi * 54, spacing: 12.1).count, 15)
    XCTAssertEqual(VoteArc.dotPositions(length: .pi * 38, spacing: 12.1).count, 11)
    XCTAssertEqual(VoteArc.dotPositions(length: 1, spacing: 50), [0, 1])
  }

  // MARK: - Instantané

  private func decode(_ extra: String) throws -> WidgetDecision? {
    let json = """
      {"version":1,"decisions":[{"id":"x","result":"adopte","date":"2026-10-13",
      "title":"Titre"\(extra)}]}
      """
    return try JSONDecoder().decode(DecisionSnapshot.self, from: Data(json.utf8)).decisions.first
  }

  func testInstantaneAvecDecompteEtMode() throws {
    let d = try XCTUnwrap(
      try decode(
        #","count":{"pour":503,"contre":0,"abstentions":67},"voteMode":"scrutin_public""#))
    XCTAssertEqual(d.count, VoteCount(pour: 503, contre: 0, abstentions: 67))
    XCTAssertEqual(d.voteMode, .scrutinPublic)
  }

  func testAncienInstantaneSansLesNouveauxChamps() throws {
    let d = try XCTUnwrap(try decode(""))
    XCTAssertNil(d.count)
    XCTAssertNil(d.voteMode)
    XCTAssertEqual(VoteArc(decision: d), .solid(.pour))
  }

  func testChampsIllisiblesIgnores() throws {
    let d = try XCTUnwrap(
      try decode(#","count":{"pour":-1,"contre":0,"abstentions":2},"voteMode":"inconnu""#))
    XCTAssertNil(d.count)
    XCTAssertNil(d.voteMode)
    XCTAssertNil(try XCTUnwrap(try decode(#","count":{"pour":3}"#)).count)
    XCTAssertNil(try XCTUnwrap(try decode(#","count":"503""#)).count)
  }

  func testMentionsDeLEtape() {
    func decision(_ stage: String?) -> WidgetDecision {
      WidgetDecision(
        id: "x", result: .adopte, date: "2026-10-13", title: "t", stage: stage, explanation: nil)
    }
    let both = decision("1re lecture à l'AN · à main levée · provisoire")
    XCTAssertEqual(both.stageWithoutMentions, "1re lecture à l'AN")
    XCTAssertEqual(both.mentions, ["à main levée", "provisoire"])
    let alone = decision("Provisoire")
    XCTAssertNil(alone.stageWithoutMentions)
    XCTAssertEqual(alone.mentions, ["provisoire"])
    XCTAssertTrue(alone.isProvisional)
    XCTAssertFalse(alone.isMainLevee)
    XCTAssertEqual(decision(nil).mentions, [])
    XCTAssertEqual(decision("Résolution").stageWithoutMentions, "Résolution")
  }
}
