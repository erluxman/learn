import AppKit
import SwiftUI

/// Temporary trace for diagnosing clicks: ~/Library/Application Support/Learn/debug.log
enum Debug {
    private static let url = ShortcutStore.shared.dir.deletingLastPathComponent().appendingPathComponent("debug.log")
    private static let q = DispatchQueue(label: "learn.debug")
    private static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()

    static func log(_ s: @autoclosure () -> String) {   // built only when logging is on
        guard UserDefaults.standard.bool(forKey: "debugLog") else { return }   // Settings ▸ General ▸ Troubleshooting
        let line = "\(fmt.string(from: Date())) \(s())\n"
        q.async {
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
            else { try? line.write(to: url, atomically: true, encoding: .utf8) }
        }
    }
}

/// Id of the Space (desktop) on screen now, for the panel-focus trace.
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSGetActiveSpace") private func CGSGetActiveSpace(_ cid: Int32) -> Int
extension Debug {
    static var space: Int { CGSGetActiveSpace(CGSMainConnectionID()) }
    static var front: String { NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?" }
}

extension Debug {
    /// A debug build (`swift build` / `swift run`); release builds from build.sh hide the badge and the Cleaner.
    #if DEBUG
    static let build = true
    #else
    static let build = false
    #endif
}

/// "DEBUG" tag for a window's top-right corner; nothing in release builds.
struct DebugBadge: View {
    @Environment(\.appearance) private var look
    var body: some View {
        if Debug.build {
            Text("DEBUG")
                .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.8)
                .foregroundStyle(.black.opacity(0.8))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.orange))
                .padding(.top, look.cornerInset(16)).padding(.trailing, look.cornerInset(18))
                .allowsHitTesting(false)
        }
    }
}
