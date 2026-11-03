import XCTest
@testable import Learn

/// Live check against Obsidian's graph view with its controls panel open: OBSIDIAN_PID=<pid> swift test.
final class ObsidianControlsTests: XCTestCase {
    func testGraphControlsAreAllListedByName() throws {
        guard let pid = ProcessInfo.processInfo.environment["OBSIDIAN_PID"].flatMap(pid_t.init) else { throw XCTSkip("OBSIDIAN_PID not set") }
        let els = ElementScanner.scan(pid: pid, budget: 3)
        let sliders = els.filter { $0.role == "AXSlider" }, switches = els.filter { $0.role == "AXCheckBox" }
        XCTAssertEqual(sliders.count, 7)
        XCTAssertEqual(switches.count, 5)
        XCTAssertEqual(switches.first?.text, "Tags")
        XCTAssertFalse(sliders.contains { Double($0.text.components(separatedBy: " · ")[0]) != nil }, "named by their setting, not their value")
        print("names:", (switches + sliders).map { "\($0.text) \($0.frame)" })
    }

    func testPressingAWebSwitchFlipsIt() throws {
        guard let pid = ProcessInfo.processInfo.environment["OBSIDIAN_PID"].flatMap(pid_t.init) else { throw XCTSkip("OBSIDIAN_PID not set") }
        let sw = try XCTUnwrap(ElementScanner.scan(pid: pid, budget: 3).first { $0.role == "AXCheckBox" && $0.text == "Existing files only" })
        func on() -> Bool {
            var p: AnyObject?, c: AnyObject?
            AXUIElementCopyAttributeValue(sw.ref, kAXParentAttribute as CFString, &p)
            AXUIElementCopyAttributeValue(p as! AXUIElement, "AXDOMClassList" as CFString, &c)
            return (c as? [String] ?? []).contains("is-enabled")
        }
        let before = on()
        ElementScanner.perform(sw); Thread.sleep(forTimeInterval: 3)
        XCTAssertNotEqual(on(), before)
        ElementScanner.perform(sw); Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(on(), before)
    }

    func testJumpingASliderToItsEndsAndBack() throws {
        guard let pid = ProcessInfo.processInfo.environment["OBSIDIAN_PID"].flatMap(pid_t.init) else { throw XCTSkip("OBSIDIAN_PID not set") }
        let s = try XCTUnwrap(ElementScanner.scan(pid: pid, budget: 3).first { $0.role == "AXSlider" && $0.text == "Text fade threshold" })
        let orig = try XCTUnwrap(AdjustMode.number(s.ref, kAXValueAttribute))
        AXUIElementSetAttributeValue(s.ref, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AdjustMode.jump(s, to: 1)
        XCTAssertEqual(AdjustMode.number(s.ref, kAXValueAttribute), AdjustMode.number(s.ref, kAXMaxValueAttribute))
        AdjustMode.jump(s, to: 0)
        XCTAssertEqual(AdjustMode.number(s.ref, kAXValueAttribute), AdjustMode.number(s.ref, kAXMinValueAttribute))
        AdjustMode.approach(orig, read: { AdjustMode.number(s.ref, kAXValueAttribute) }, step: { AdjustMode.step(s, up: $0) })
        XCTAssertEqual(try XCTUnwrap(AdjustMode.number(s.ref, kAXValueAttribute)), orig, accuracy: 0.001, "fine steps get it back exactly")
    }
}
