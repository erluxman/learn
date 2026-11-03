import XCTest
@testable import Learn

final class LabelPlacementTests: XCTestCase {
    func testLabelsOnTheSameSpotSpreadOutWithoutOverlapping() {
        let size = CGSize(width: 24, height: 16)
        let boxes = Array(repeating: (anchor: CGPoint(x: 100, y: 100), size: size), count: 9)
            + [(anchor: CGPoint(x: 500, y: 500), size: size)]
        let at = Overlay.place(boxes)
        XCTAssertEqual(at[0], CGPoint(x: 100, y: 100), "the first keeps its spot")
        XCTAssertEqual(at[9], CGPoint(x: 500, y: 500), "a label with room stays put")
        let rects = at.map { CGRect(origin: $0, size: size) }
        for i in rects.indices { for j in rects.indices where i < j { XCTAssertFalse(rects[i].intersects(rects[j]), "\(i) overlaps \(j)") } }
        XCTAssertTrue(at.allSatisfy { abs($0.x - 100) <= 4 * 26 || $0.x == 500 }, "stays near its item")
    }
}
