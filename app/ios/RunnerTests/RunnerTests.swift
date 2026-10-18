import XCTest

/// Tests de la sélection des décisions affichées par les widgets
/// (`DecisionWidget/DecisionSnapshot.swift`, compilé aussi dans cette cible).
final class WidgetSelectionTests: XCTestCase {
  private func snapshot(_ ids: [String]) -> DecisionSnapshot {
    DecisionSnapshot(
      version: 1,
      decisions: ids.map {
        WidgetDecision(
          id: $0, result: .adopte, date: "2026-10-13", title: "Titre \($0)", stage: nil,
          explanation: nil)
      })
  }

  func testGrandWidgetLesTroisPlusRecentesDansLOrdre() {
    let latest = snapshot(["a", "b", "c", "d", "e"]).latest(DecisionSnapshot.largeWidgetCount)
    XCTAssertEqual(latest.map(\.id), ["a", "b", "c"])
  }

  func testMoinsDeDecisionsQueDemande() {
    XCTAssertEqual(snapshot(["a", "b"]).latest(3).map(\.id), ["a", "b"])
    XCTAssertEqual(snapshot([]).latest(3).map(\.id), [])
  }

  func testPetitEtMoyenLaDerniere() {
    XCTAssertEqual(snapshot(["a", "b", "c"]).latest(1).map(\.id), ["a"])
  }

  func testNombreNulOuNegatif() {
    XCTAssertEqual(snapshot(["a"]).latest(0).map(\.id), [])
    XCTAssertEqual(snapshot(["a"]).latest(-1).map(\.id), [])
  }
}
