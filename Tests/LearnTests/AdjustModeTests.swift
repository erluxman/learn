import XCTest
@testable import Learn

final class AdjustModeTests: XCTestCase {
    func testKeys() {
        XCTAssertEqual(AdjustMode.action(keyCode: 124, mods: []), .step(1))       // →
        XCTAssertEqual(AdjustMode.action(keyCode: 4, mods: []), .step(-1))        // H
        XCTAssertEqual(AdjustMode.action(keyCode: 123, mods: [.shift]), .step(-10))
        XCTAssertEqual(AdjustMode.action(keyCode: 23, mods: []), .percent(0.5))   // 5
        XCTAssertEqual(AdjustMode.action(keyCode: 21, mods: [.shift]), .percent(1)) // $
        XCTAssertEqual(AdjustMode.action(keyCode: 53, mods: []), .done)
        XCTAssertNil(AdjustMode.action(keyCode: 0, mods: [.cmd]))
    }

    /// A slider that only moves by steps of 1 between -3 and 3.
    private func run(from start: Double, to goal: Double) -> Double {
        var v = start
        AdjustMode.approach(goal, read: { v }, step: { up in v = min(3, max(-3, v + (up ? 1 : -1))) })
        return v
    }

    func testApproachStopsOnTheNearerSideOfTheGoal() {
        XCTAssertEqual(run(from: -0.8, to: 1.9), 2.2, accuracy: 1e-9)   // 1.2 → 2.2 crosses; 2.2 is nearer
        XCTAssertEqual(run(from: -0.8, to: 1.5), 1.2, accuracy: 1e-9)   // 2.2 overshoots more than 1.2 undershoots
        XCTAssertEqual(run(from: 0, to: -9), -3)                         // pinned at the end: stops
        XCTAssertEqual(run(from: 1, to: 1), 1)
    }
}
