import AppKit

/// Extra words a row also answers to, so "move window to laptop" finds "Move to Built-in Retina Display"
/// even if you don't know the display's real name. Covers Learn's commands and apps' own menu items.
enum Synonyms {
    private static let words: [String: String] = [
        "display": "screen monitor", "screen": "display monitor", "monitor": "display screen",
        "displays": "screens monitors", "screens": "displays monitors",
        "move": "send put throw switch", "next": "other another second", "window": "app",
        "minimize": "hide dock", "zoom": "maximize fill", "fullscreen": "maximize", "full": "maximize",
        "tile": "split snap side", "arrange": "tile split snap", "mirror": "duplicate",
        "sidecar": "ipad tablet", "airplay": "ipad cast", "screenshot": "capture grab snap",
    ]

    /// Lowercased display name → what people call it. Refreshed each time the panel opens.
    private(set) static var screens: [String: String] = [:]

    static func refreshScreens() {
        var out: [String: String] = [:]
        for s in NSScreen.screens {
            let n = s.localizedName.lowercased()
            if n.contains("built-in") || n.contains("color lcd") {
                out[n] = "laptop internal macbook builtin main mac"
            } else if n.contains("sidecar") {
                out[n] = "ipad tablet sidecar airplay second"
            } else {
                out[n] = "external monitor second other"
            }
        }
        screens = out
    }

    /// `text` (lowercased) plus the synonyms of every word and display name in it.
    static func expand(_ text: String) -> String {
        var extra: [String] = []
        for (name, aliases) in screens where text.contains(name) { extra.append(aliases) }
        if text.contains("ipad (sidecar)") { extra.append("tablet airplay second") }   // Learn's own name for Sidecar
        for w in text.split(separator: " ") { if let s = words[String(w)] { extra.append(s) } }
        return extra.isEmpty ? text : text + " " + extra.joined(separator: " ")
    }
}
