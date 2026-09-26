import AppKit

/// Runs a shortcut in its app: activate app → press the menu item via AX; fall back to a synthesized keystroke.
enum Executor {
    static func run(_ s: Shortcut, in app: AppEntry) {
        DispatchQueue.main.async { Sounds.play(.shortcut) }
        DispatchQueue.main.async { KeyHUD.shared.flash(s.display, caption: s.title) }
        if app.isSystem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { postKey(s) }
            return
        }
        if let running = app.runningApp {
            NSApp.yieldActivation(to: running)
            running.unhide()
            running.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { press(s, pid: running.processIdentifier) }
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: cfg) { launched, _ in
            guard let launched else { return }
            DispatchQueue.global().async {
                _ = Scanner.waitForMenus(pid: launched.processIdentifier, timeout: 8)
                DispatchQueue.main.async { press(s, pid: launched.processIdentifier) }
            }
        }
    }

    private static func press(_ s: Shortcut, pid: pid_t) {
        if MenuScanner.press(path: s.path, pid: pid) { return }
        if !s.isCustom { postKey(s) }   // posting a custom combo would just loop back through our tap
        else { NSSound.beep() }
    }

    static func postKey(_ s: Shortcut) {
        var mods = s.mods
        var code = s.keyCode
        if code == nil, let (c, needsShift) = Keys.code(for: s.key) {
            code = c
            if needsShift { mods.insert(.shift) }
        }
        guard let code else { NSSound.beep(); return }
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: down)
            e?.flags = mods.cgFlags
            e?.post(tap: .cghidEventTap)
        }
    }
}
