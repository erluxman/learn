import XCTest
@testable import Learn

/// Live check against an Electron app whose AX window list is empty (Powerdeck, Obsidian): ELECTRON_PID=<pid> swift test.
final class ElectronWindowTests: XCTestCase {
    /// Label mode pairs each on-screen window with its AX window; Electron only reports a focused / main one.
    func testLabelModeFindsAnElectronWindowByItsFrame() throws {
        guard let pid = ProcessInfo.processInfo.environment["ELECTRON_PID"].flatMap(pid_t.init) else { throw XCTSkip("ELECTRON_PID not set") }
        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        let frame = try XCTUnwrap(list.lazy.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
            .compactMap { ($0[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) } }
            .first { $0.height > 300 })
        XCTAssertNotNil(ElementScanner.axWindow(pid: pid, frame: frame))
    }
}
