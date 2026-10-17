import XCTest

/// Tests de `RelativeDate` (extension DecisionWidget), dont le fichier est aussi
/// compilé dans cette cible.
final class RelativeDateTests: XCTestCase {
  private var paris: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
  }

  private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, _ s: Int = 0)
    -> Date
  {
    paris.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
  }

  private func label(_ day: String, _ now: Date) -> String {
    RelativeDate.label(day: day, now: now, calendar: paris)
  }

  func testAujourdhuiPuisHierAMinuit() {
    XCTAssertEqual(label("2026-10-16", at(2026, 10, 16, 0, 0)), "Aujourd'hui")
    XCTAssertEqual(label("2026-10-16", at(2026, 10, 16, 23, 59, 59)), "Aujourd'hui")
    XCTAssertEqual(label("2026-10-16", at(2026, 10, 17, 0, 0)), "Hier")
  }

  func testJoursDeCalendrierWeekEndCompris() {
    // Vote du vendredi 16 octobre 2026, lu le lundi.
    XCTAssertEqual(label("2026-10-16", at(2026, 10, 19, 8)), "Il y a 3 jours")
    XCTAssertEqual(label("2026-10-16", at(2026, 10, 22, 23)), "Il y a 6 jours")
  }

  func testDateCompleteAuDelaDeSixJours() {
    XCTAssertEqual(label("2026-10-16", at(2026, 10, 23)), "16 octobre 2026")
    XCTAssertEqual(label("2026-09-01", at(2026, 10, 17)), "1er septembre 2026")
  }

  func testChangementDHeureEtDateFuture() {
    // Passage à l'heure d'hiver le 25 octobre 2026.
    XCTAssertEqual(label("2026-10-24", at(2026, 10, 25, 23)), "Hier")
    XCTAssertEqual(label("2026-12-31", at(2027, 1, 1, 0, 30)), "Hier")
    XCTAssertEqual(label("2026-10-16", at(2026, 10, 15)), "Aujourd'hui")
  }

  func testJourIllisible() {
    XCTAssertEqual(label("pas-une-date", at(2026, 10, 17)), "pas-une-date")
  }
}
