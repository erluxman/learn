import XCTest
@testable import Learn

final class WheelScrollTests: XCTestCase {
    func testHeldSpeedEasesFromOneToAHundred() {
        XCTAssertEqual(WheelScroll.speed(held: 0), 1)
        XCTAssertEqual(WheelScroll.speed(held: WheelScroll.ramp / 2), 50.5, accuracy: 1e-9)
        XCTAssertEqual(WheelScroll.speed(held: WheelScroll.ramp), 100)
        XCTAssertEqual(WheelScroll.speed(held: 60), 100)
        let early = WheelScroll.speed(held: 0.1) - WheelScroll.speed(held: 0)
        let middle = WheelScroll.speed(held: WheelScroll.ramp / 2 + 0.1) - WheelScroll.speed(held: WheelScroll.ramp / 2)
        XCTAssertLessThan(early, middle, "eases in: slow start, then faster")
    }

    func testReleasedSpeedEasesOutToOneThenStops() {
        XCTAssertEqual(WheelScroll.coast(from: 80, after: 0), 80)
        let a = WheelScroll.coast(from: 80, after: 0.1)!, b = WheelScroll.coast(from: 80, after: 0.2)!
        XCTAssertLessThan(b, a)
        XCTAssertGreaterThanOrEqual(b, 1)
        XCTAssertGreaterThan(80 - a, a - b, "eases out: drops fast, then settles")
        XCTAssertNil(WheelScroll.coast(from: 80, after: WheelScroll.fall))
    }

    func testDirections() {
        XCTAssertEqual(WheelScroll.direction(code: 126, spaceHeld: false, inText: true), .up, "⌘↑ scrolls even in VS Code's editor")
        XCTAssertEqual(WheelScroll.direction(code: 125, spaceHeld: false, inText: false), .down)
        XCTAssertEqual(WheelScroll.direction(code: 123, spaceHeld: false, inText: false), .left, "⌘← outside text: no Back, a sideways scroll")
        XCTAssertNil(WheelScroll.direction(code: 123, spaceHeld: false, inText: true), "⌘← in text: start of line")
        XCTAssertEqual(WheelScroll.direction(code: 124, spaceHeld: true, inText: true), .right, "⌘Space + → scrolls even in text")
        XCTAssertNil(WheelScroll.direction(code: 0, spaceHeld: true, inText: false))
    }
}
