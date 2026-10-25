import XCTest

/// Tests des sièges de l'hémicycle des widgets (#78) : lecture du détail, forme de l'instantané,
/// géométrie (`DecisionWidget/HemicycleSeats.swift` et `HemicycleGeometry.swift`, compilés aussi
/// dans cette cible).
final class HemicycleSeatsTests: XCTestCase {
  private func detail(_ seats: String, id: String = "VTANR5L17V8706") -> Data {
    Data(
      """
      {"schemaVersion":1,"decision":{"id":"\(id)"},"seats":\(seats)}
      """.utf8)
  }

  func testDetailVersInstantane() throws {
    let votes = try XCTUnwrap(
      SeatVotes.fromDetail(
        detail(#"[[1,"PO1","p"],[5,"PO2","c"],[3,"PO1","a"],[6,"PO3","n"],[7,"PO3","x"]]"#),
        id: "VTANR5L17V8706"))
    XCTAssertEqual(votes.encoded, "p-a-cnx")
    XCTAssertEqual(SeatVotes(encoded: votes.encoded), votes)
    XCTAssertEqual(votes.byPlace[5], .contre)
  }

  func testDetailIllisibleOuDUneAutreDecision() {
    let ok = #"[[1,"PO1","p"]]"#
    XCTAssertNil(SeatVotes.fromDetail(detail(ok), id: "autre"))
    XCTAssertNil(SeatVotes.fromDetail(Data(#"{"schemaVersion":2,"decision":{"id":"a"},"seats":[[1,"P","p"]]}"#.utf8), id: "a"))
    for seats in [
      "[]", "null", #"[[1,"PO1","z"]]"#, #"[[0,"PO1","p"]]"#, #"[[1,"PO1","p"],[1,"PO2","c"]]"#,
      #"[[1,"","p"]]"#, #"[[1.5,"PO1","p"]]"#, #"[[true,"PO1","p"]]"#, #"[[1,"PO1"]]"#,
    ] {
      XCTAssertNil(SeatVotes.fromDetail(detail(seats), id: "VTANR5L17V8706"), seats)
    }
  }

  func testInstantaneIllisible() {
    XCTAssertNil(SeatVotes(encoded: nil))
    XCTAssertNil(SeatVotes(encoded: ""))
    XCTAssertNil(SeatVotes(encoded: "---"))
    XCTAssertNil(SeatVotes(encoded: "ppz"))
    XCTAssertNil(SeatVotes(encoded: 42))
    XCTAssertNil(SeatVotes(encoded: String(repeating: "p", count: 1001)))
  }

  func testGeometrieDuPlan() {
    XCTAssertEqual(HemicycleGeometry.places.count, 582)
    XCTAssertEqual(HemicycleGeometry.xs.count, 582)
    XCTAssertEqual(HemicycleGeometry.ys.count, 582)
    XCTAssertEqual(HemicycleGeometry.places, HemicycleGeometry.places.sorted())
    XCTAssertEqual(Set(HemicycleGeometry.places).count, 582)
    let box = HemicycleGeometry.viewBox
    for (x, y) in zip(HemicycleGeometry.xs, HemicycleGeometry.ys) {
      XCTAssert((box.x...(box.x + box.width)).contains(x))
      XCTAssert((box.y...(box.y + box.height)).contains(y))
    }
    // Place 1 à droite du centre, la dernière à l'extrême gauche (vu du perchoir).
    XCTAssertEqual(HemicycleGeometry.places.first, 1)
    XCTAssertEqual(HemicycleGeometry.xs.first, 159.79)
    XCTAssertEqual(HemicycleGeometry.places.last, 650)
    XCTAssertEqual(HemicycleGeometry.xs.last, HemicycleGeometry.xs.min())
  }

  func testDispositionParVote() throws {
    let votes = try XCTUnwrap(SeatVotes(encoded: "pc-xanx"))
    let layout = HemicycleLayout(votes: votes)
    // Place 3 sans député ; la place 4 n'existe pas sur le plan : rien n'est dessiné.
    XCTAssertEqual(layout.count, 5)
    XCTAssertEqual(layout.dots[.pour], [HemicycleLayout.Point(x: 159.79, y: 117.92)])
    XCTAssertEqual(layout.dots[.contre]?.count, 1)
    XCTAssertEqual(layout.dots[.abstention]?.count, 1)
    XCTAssertEqual(layout.dots[.off]?.count, 2)
    XCTAssertEqual(HemicycleLayout.Kind.abstention.radiusScale, 0.5)
  }

  func testExempleDe8706() throws {
    let layout = HemicycleLayout(votes: try XCTUnwrap(SeatVotes(encoded: HemicycleGeometry.sampleVotes)))
    XCTAssertEqual(layout.count, 574)
    XCTAssertEqual(layout.dots[.pour]?.count, 503)
    XCTAssertNil(layout.dots[.contre])
    XCTAssertEqual(layout.dots[.abstention]?.count, 67)
  }

  func testLibelleDAccessibilite() {
    let decision = WidgetDecision(
      id: "a", result: .adopte, date: "2026-10-13", title: "Juges des violences sexuelles",
      stage: "1re lecture · provisoire", explanation: nil,
      count: VoteCount(pour: 503, contre: 0, abstentions: 67))
    XCTAssertEqual(
      decision.accessibilityLabel,
      "Adopté. Juges des violences sexuelles. 503 pour, 0 contre, 67 abstentions. Décision provisoire.")
    let mainLevee = WidgetDecision(
      id: "b", result: .rejete, date: "2026-10-13", title: "Accord.", stage: nil,
      explanation: nil, voteMode: .mainLevee)
    XCTAssertEqual(mainLevee.accessibilityLabel, "Rejeté. Accord. Vote à main levée.")
  }

  func testLibellesDuProchainVote() throws {
    let vote = UpcomingVote(
      id: "v", startsAt: try XCTUnwrap(UpcomingVote.instant("2026-11-03T14:00:00Z")),
      title: "Budget de l'État 2027")
    XCTAssertEqual(vote.whenLabel, "Vote · mar. 15 h")
    XCTAssertEqual(vote.accessibilityLabel, "Prochain vote solennel, mar. 3 nov. à 15 h. Budget de l'État 2027")
    let late = UpcomingVote(
      id: "w", startsAt: try XCTUnwrap(UpcomingVote.instant("2026-07-01T19:30:00Z")), title: "T")
    XCTAssertEqual(late.timeLabel, "21 h 30")
    XCTAssertEqual(late.dayOfMonthLabel, "1er")
  }

  func testDateCourte() {
    let d = WidgetDecision(
      id: "a", result: .adopte, date: "2026-10-08", title: "T", stage: nil, explanation: nil)
    XCTAssertEqual(d.shortDateLabel, "8 oct.")
  }
}
