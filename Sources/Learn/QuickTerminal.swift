import AppKit

/// Ghostty's quick terminal (the drop-down) hides the moment it stops being the key window when `quick-terminal-autohide`
/// is on, and Learn's panel has to take the keyboard — so opening Learn over it always hid it. Learn grabs it as the
/// panel opens (its contents stay readable after it hides) and brings it back through Ghostty's AppleScript
/// (`perform action "toggle_quick_terminal"`) before running something in it, or when the panel is cancelled.
enum QuickTerminal {
    static let ghostty = "com.mitchellh.ghostty"
    private static let identifier = "com.mitchellh.ghostty.quickTerminal"

    /// The quick terminal window that was open when the panel opened; nil when there was none.
    private(set) static var window: AXUIElement?

    /// Call before the panel takes the keyboard.
    static func capture(_ app: NSRunningApplication?) {
        window = app?.bundleIdentifier == ghostty ? find(app!.processIdentifier) : nil
    }

    static func forget() { window = nil }

    /// Shows it again if it was open when the panel opened (and `appID` is Ghostty), then runs `then` once it has slid in.
    /// Otherwise runs `then` right away.
    static func restore(for appID: String? = ghostty, then: @escaping () -> Void = {}) {
        guard window != nil, appID == ghostty, let app = NSRunningApplication.runningApplications(withBundleIdentifier: ghostty).first
        else { forget(); return then() }
        forget()
        guard find(app.processIdentifier) == nil else { return then() }   // autohide off: it never left
        var err: NSDictionary?
        NSAppleScript(source: "tell application id \"\(ghostty)\" to perform action \"toggle_quick_terminal\" on terminal 1")?
            .executeAndReturnError(&err)
        if let err { Debug.log("quick terminal restore failed: \(err)") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: then)   // its slide-in
    }

    /// The quick terminal's window while it's on screen (it's only listed then).
    private static func find(_ pid: pid_t) -> AXUIElement? {
        let ax = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(ax, 0.2)
        var list: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &list) == .success,
              let windows = list as? [AXUIElement] else { return nil }
        return windows.first { w in
            var id: CFTypeRef?
            AXUIElementCopyAttributeValue(w, kAXIdentifierAttribute as CFString, &id)
            return id as? String == identifier
        }
    }
}
