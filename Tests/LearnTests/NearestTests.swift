import XCTest
@testable import Learn

final class NearestTests: XCTestCase {
    let from = CGRect(x: 100, y: 100, width: 20, height: 20)

    func testRightPicksTheItemBesideOverOneFurtherOnTheSameRowOrBelow() {
        let els = ["beside": CGRect(x: 140, y: 100, width: 20, height: 20),
                   "far": CGRect(x: 400, y: 100, width: 20, height: 20),
                   "belowRight": CGRect(x: 130, y: 200, width: 20, height: 20),
                   "left": CGRect(x: 50, y: 100, width: 20, height: 20)]
        XCTAssertEqual(SearchModel.nearest(from, 1, in: els), "beside")
        XCTAssertEqual(SearchModel.nearest(from, -1, in: els), "left")
    }

    func testNothingThatWayGivesNil() {
        XCTAssertNil(SearchModel.nearest(from, 1, in: ["left": CGRect(x: 50, y: 100, width: 20, height: 20), "self": from]))
    }
}
