import XCTest
@testable import Learn

final class LabelModeTests: XCTestCase {
    func testLabelsLeaveMFreeForThePointerPrefixAndNoneIsAPrefixOfAnother() {
        let labels = HintMode.labels(700)
        XCTAssertEqual(Set(labels).count, 700)
        XCTAssertFalse(labels.contains { $0.contains("M") })
        XCTAssertFalse(labels.contains { a in labels.contains { $0 != a && $0.hasPrefix(a) } })
    }

    func testItemsUnderAWindowInFrontAreDropped() {
        func item(_ x: CGFloat, _ y: CGFloat, _ t: String) -> ScreenElement {
            ScreenElement(ref: AXUIElementCreateSystemWide(), role: "AXButton", roleName: "Button", text: t,
                          frame: CGRect(x: x, y: y, width: 10, height: 10))
        }
        let front = CGRect(x: 0, y: 0, width: 100, height: 100)
        let back = CGRect(x: 50, y: 50, width: 200, height: 200)
        let otherScreen = CGRect(x: 2000, y: 0, width: 300, height: 300)
        let kept = ElementScanner.unhidden([(front, [item(10, 10, "front")]),
                                            (back, [item(60, 60, "covered"), item(150, 150, "showing")]),
                                            (otherScreen, [item(2010, 10, "other screen")])])
        XCTAssertEqual(kept.map(\.text), ["front", "showing", "other screen"])
    }
}
