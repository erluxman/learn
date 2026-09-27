import AppKit

/// Ghostty's quick terminal (the drop-down) hides the moment it stops being the key window when `quick-terminal-autohide`
/// is on, and Learn's panel has to take the keyboard — so opening Learn over it always hid it. Learn grabs it as the
/// panel opens (its contents stay readable after it hides) and brings it back through Ghostty's AppleScript
/// (`perform action "toggle_quick_terminal"`) after the panel has closed — before running something in it, or on cancel.
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

    /// Whether it should come back for something done in `appID` (it was open and that's Ghostty). Clears the note either
    /// way, so take it before closing the panel.
    static func take(for appID: String? = ghostty) -> Bool {
        defer { forget() }
        return window != nil && appID == ghostty
    }

    /// Ghostty, while its quick terminal is on screen — that's where you are. On a desktop with no Ghostty window, macOS
    /// refuses Ghostty's activation when it slides in (ghostty#2409): the quick terminal has the keyboard, but the app you
    /// were in before stays "frontmost". (With autohide on, it's only on screen while it has the keyboard.)
    static func ghosttyIfOnScreen() -> NSRunningApplication? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: ghostty).first,
              find(app.processIdentifier) != nil else { return nil }
        return app
    }

    /// Slides it back in (the panel must be closed by now, or it takes the keyboard and hides it again), then runs `then`.
    static func bringBack(then: @escaping () -> Void = {}) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: ghostty).first else { return then() }
        guard find(app.processIdentifier) == nil else { Debug.log("quick terminal still up"); return then() }   // autohide off: it never left
        Debug.log("quick terminal restore space=\(Debug.space)")
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
