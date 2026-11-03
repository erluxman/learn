import XCTest
@testable import Learn

/// Live check against a YouTube video playing in Brave: BRAVE_PID=<pid> swift test --filter BraveVideo.
final class BraveVideoTests: XCTestCase {
    func testSeekSliderStepsForwardAndBack() throws {
        guard let pid = ProcessInfo.processInfo.environment["BRAVE_PID"].flatMap(pid_t.init) else { throw XCTSkip("BRAVE_PID not set") }
        let s = try XCTUnwrap(ElementScanner.scan(pid: pid, budget: 3).first { $0.role == "AXSlider" && $0.text.contains("Seek") })
        ElementScanner.bringToFront(s)
        AXUIElementSetAttributeValue(s.ref, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        let before = try XCTUnwrap(AdjustMode.number(s.ref, kAXValueAttribute))
        AdjustMode.step(s, up: true)
        let after = try XCTUnwrap(AdjustMode.number(s.ref, kAXValueAttribute))
        print("seek", before, "→", after, "focused", AdjustMode.number(s.ref, kAXFocusedAttribute) ?? -1)
        XCTAssertGreaterThan(after - before, 2, "an arrow step seeks ~5 s, more than playback moves meanwhile")
        AdjustMode.step(s, up: false)
    }
}
