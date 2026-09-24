import Foundation

/// Optional: Learn takes ⌘Space from Spotlight. Rewrites Spotlight's entry (#64) in com.apple.symbolichotkeys —
/// the same thing System Settings ▸ Keyboard Shortcuts ▸ Spotlight writes — and applies it without logging out.
enum SpotlightKey {
    enum Mode: String, CaseIterable {
        case keep      // Spotlight keeps ⌘Space
        case replace   // Learn gets ⌘Space, Spotlight's shortcut is off
        case swap      // Learn gets ⌘Space, Spotlight moves to ⌥Space
    }

    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let cmd = 0x100000, opt = 0x80000
    static let learnKey = Binding(path: Prefs.defaultPanelKey.path, keyCode: 49, mods: [.cmd])   // ⌘Space

    /// Read back from macOS, so edits made in System Settings show up too.
    static var current: Mode {
        guard let e = SystemShortcuts.raw()["64"] as? [String: Any] else { return .keep }
        if (e["enabled"] as? NSNumber)?.boolValue == false { return .replace }
        let p = ((e["value"] as? [String: Any])?["parameters"] as? [NSNumber])?.map(\.intValue) ?? []
        return p.count == 3 && p[1] == 49 && p[2] == opt ? .swap : .keep
    }

    /// Main thread. System change off main (activateSettings takes ~1s), then Learn's panel key follows.
    static func apply(_ mode: Mode) {
        UserDefaults.standard.set(mode.rawValue, forKey: "spotlightMode")   // uninstall.sh restores Spotlight from this
        DispatchQueue.global(qos: .userInitiated).async {
            var all = SystemShortcuts.raw()
            all["64"] = ["enabled": mode != .replace,
                         "value": ["type": "standard", "parameters": [32, 49, mode == .swap ? opt : cmd]]] as [String: Any]
            CFPreferencesSetAppValue("AppleSymbolicHotKeys" as CFString, all as CFDictionary, domain)
            CFPreferencesAppSynchronize(domain)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
            p.arguments = ["-u"]
            try? p.run()
            p.waitUntilExit()
            Debug.log("spotlight key → \(mode.rawValue), activateSettings exit \(p.isRunning ? -1 : p.terminationStatus)")
            DispatchQueue.main.async {
                let prefs = Prefs.shared
                if mode == .keep { if prefs.panelKey == learnKey { prefs.panelKey = Prefs.defaultPanelKey } }
                else { prefs.panelKey = learnKey }
                // Spotlight may let go of ⌘Space a moment later: register the panel hotkey again.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { NotificationCenter.default.post(name: Prefs.changed, object: nil) }
            }
        }
    }
}
