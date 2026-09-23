import Foundation

/// macOS global shortcuts from com.apple.symbolichotkeys (System Settings ▸ Keyboard ▸ Keyboard Shortcuts).
enum SystemShortcuts {
    static let bundleID = "learn.system-shortcuts"
    static let entry = AppEntry(id: bundleID, name: "macOS System Shortcuts",
                                url: URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    private static let domain = "com.apple.symbolichotkeys" as CFString

    // id → (group, name)
    static let names: [Int: (String, String)] = {
        var n: [Int: (String, String)] = [
            7: ("Keyboard", "Move focus to the menu bar"), 8: ("Keyboard", "Move focus to the Dock"),
            9: ("Keyboard", "Move focus to active or next window"), 10: ("Keyboard", "Move focus to window toolbar"),
            11: ("Keyboard", "Move focus to floating window"), 12: ("Keyboard", "Turn keyboard access on or off"),
            13: ("Keyboard", "Change the way Tab moves focus"), 27: ("Keyboard", "Move focus to next window"),
            57: ("Keyboard", "Move focus to status menus"), 159: ("Keyboard", "Turn focus following on or off"),
            15: ("Accessibility", "Turn zoom on or off"), 17: ("Accessibility", "Zoom in"),
            19: ("Accessibility", "Zoom out"), 21: ("Accessibility", "Invert colors"),
            23: ("Accessibility", "Turn image smoothing on or off"), 25: ("Accessibility", "Increase contrast"),
            26: ("Accessibility", "Decrease contrast"), 59: ("Accessibility", "Turn VoiceOver on or off"),
            162: ("Accessibility", "Show Accessibility controls"),
            28: ("Screenshots", "Save picture of screen as a file"),
            29: ("Screenshots", "Copy picture of screen to the clipboard"),
            30: ("Screenshots", "Save picture of selected area as a file"),
            31: ("Screenshots", "Copy picture of selected area to the clipboard"),
            184: ("Screenshots", "Screenshot and recording options"),
            32: ("Mission Control", "Mission Control"), 33: ("Mission Control", "Application windows"),
            36: ("Mission Control", "Show Desktop"), 79: ("Mission Control", "Move left a space"),
            81: ("Mission Control", "Move right a space"), 163: ("Mission Control", "Show Notification Center"),
            175: ("Mission Control", "Turn Do Not Disturb on or off"), 190: ("Mission Control", "Quick Note"),
            160: ("Launchpad & Dock", "Show Launchpad"), 52: ("Launchpad & Dock", "Turn Dock hiding on or off"),
            60: ("Input Sources", "Select the previous input source"),
            61: ("Input Sources", "Select next source in Input menu"),
            64: ("Spotlight", "Show Spotlight search"), 65: ("Spotlight", "Show Finder search window"),
            70: ("Services", "Look up in Dictionary"), 98: ("App Shortcuts", "Show Help menu"),
        ]
        for i in 0..<16 { n[118 + i] = ("Mission Control", "Switch to Desktop \(i + 1)") }
        return n
    }()

    // Factory defaults used when the plist has no entry: id → (keyCode, NSEvent flags)
    private static let defaults: [Int: (Int, Int)] = [
        28: (20, 0x120000), 29: (20, 0x160000), 30: (21, 0x120000), 31: (21, 0x160000), 184: (23, 0x120000),
        64: (49, 0x100000), 65: (49, 0x180000), 32: (126, 0x840000), 33: (125, 0x840000),
        79: (123, 0x840000), 81: (124, 0x840000), 36: (103, 0x800000), 27: (50, 0x100000),
        60: (49, 0x40000), 61: (49, 0xC0000), 98: (44, 0x120000), 52: (2, 0x180000), 59: (96, 0x100000),
        7: (120, 0x840000), 8: (99, 0x840000), 9: (118, 0x840000), 10: (96, 0x840000), 11: (97, 0x840000),
        12: (122, 0x840000), 13: (98, 0x840000), 57: (100, 0x840000), 70: (2, 0x140000),
    ]

    // Fixed shortcuts that aren't configurable in System Settings.
    private static let fixed: [Shortcut] = [
        Shortcut(path: ["System", "Force Quit Applications"], key: "⎋", keyCode: 53, mods: [.cmd, .opt]),
        Shortcut(path: ["System", "Lock Screen"], key: "Q", keyCode: 12, mods: [.cmd, .ctrl]),
        Shortcut(path: ["System", "Log Out…"], key: "Q", keyCode: 12, mods: [.cmd, .shift]),
        Shortcut(path: ["System", "Emoji & Symbols"], key: "Space", keyCode: 49, mods: [.cmd, .ctrl]),
        Shortcut(path: ["System", "Switch apps"], key: "⇥", keyCode: 48, mods: [.cmd]),
        Shortcut(path: ["System", "Hide front app"], key: "H", keyCode: 4, mods: [.cmd]),
        Shortcut(path: ["System", "Hide other apps"], key: "H", keyCode: 4, mods: [.cmd, .opt]),
        Shortcut(path: ["System", "Minimize window"], key: "M", keyCode: 46, mods: [.cmd]),
        Shortcut(path: ["System", "Quit front app"], key: "Q", keyCode: 12, mods: [.cmd]),
    ]

    static func raw() -> [String: Any] {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any] ?? [:]
    }

    /// Fingerprint used to detect edits made in System Settings.
    static func signature() -> String {
        guard let d = try? PropertyListSerialization.data(fromPropertyList: raw(), format: .binary, options: 0)
        else { return "" }
        return d.base64EncodedString()
    }

    static func load() -> AppShortcuts {
        var merged: [Int: (Bool, Int, Int)] = defaults.mapValues { (true, $0.0, $0.1) }
        for (k, v) in raw() {
            guard let id = Int(k), let d = v as? [String: Any] else { continue }
            let enabled = (d["enabled"] as? NSNumber)?.boolValue ?? true
            let p = ((d["value"] as? [String: Any])?["parameters"] as? [NSNumber])?.map(\.intValue) ?? []
            if p.count == 3, p[1] != 65535 { merged[id] = (enabled, p[1], p[2]) }
            else if !enabled { merged[id] = (false, 0, 0) }
        }
        var out = fixed
        for (id, (enabled, code, flags)) in merged.sorted(by: { $0.key < $1.key }) where enabled {
            let (group, name) = names[id] ?? ("Other", "System hotkey #\(id)")
            out.append(Shortcut(path: [group, name], key: Keys.names[code] ?? "key \(code)", keyCode: code,
                                mods: Mods(nsFlags: flags)))
        }
        return AppShortcuts(bundleID: bundleID, scannedAt: Date(), shortcuts: out, customSig: signature())
    }
}
