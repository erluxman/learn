import AppKit
import SwiftUI
import AVFoundation
import Speech
#if canImport(FoundationModels)
import FoundationModels
#endif

/// AI Config's layers of understanding, each built on a model that runs on this Mac: one inside Learn, one from
/// macOS (speech), one needs Apple Intelligence. The user switches each one on or off in AI Config ▸ Models,
/// and every reply says which layer understood it.
enum AILayer: String, CaseIterable, Identifiable {
    case semantic, voice, appleIntelligence, localModel
    var id: Self { self }

    var title: String {
        switch self {
        case .semantic: "Semantic model"
        case .voice: "Voice"
        case .appleIntelligence: "Apple Intelligence"
        case .localModel: "Local language model"
        }
    }
    var symbol: String {
        switch self {
        case .semantic: "point.3.connected.trianglepath.dotted"
        case .voice: "waveform"
        case .appleIntelligence: "apple.intelligence"
        case .localModel: "cpu.fill"
        }
    }
    var color: Color {
        switch self {
        case .semantic: .teal
        case .voice: .pink
        case .appleIntelligence: .purple
        case .localModel: .gray
        }
    }
    /// What it needs, in plain words.
    var needs: String {
        switch self {
        case .semantic: "Comes inside Learn (33 MB): paraphrase-MiniLM-L3, a 17-million-parameter model that turns a sentence into its meaning. Runs on the Neural Engine in milliseconds."
        case .voice: "Uses macOS's on-device speech model (downloaded with Dictation) and its voices. Better voices are a free download in System Settings."
        case .appleIntelligence: "Apple's on-device model (a few GB). Needs macOS 26, Apple silicon, and Apple Intelligence turned on in System Settings."
        case .localModel: "An open model Learn would download itself (about 1 GB), for Macs without Apple Intelligence."
        }
    }
    /// What turning it on lets you do.
    var abilities: [String] {
        switch self {
        case .semantic: ["Understands meaning, not keywords: “that menu is not necessary” = “I don't want that menu” = hide menu commands",
                         "Complaints and wishes: “the sound is too loud”, “I don't like the green background”, “the popup with my keys is annoying”",
                         "Shortcuts: “when I press ⌃⌥S, open Safari”, “I accidentally made that shortcut, remove it”",
                         "When it's torn between two meanings it asks, and remembers your answer",
                         "Tested: 44 of 55 new phrasings right on its own; nearly all the rest become a question, not a wrong change"]
        case .voice: ["Talk instead of typing, and hear the answer",
                      "Recognized on this Mac: nothing you say is sent anywhere",
                      "Type to get text back, talk to get a spoken answer"]
        case .appleIntelligence: ["Takes over when the semantic model isn't sure",
                                  "Vague wishes: “make it calm and quiet”; several changes from one idea",
                                  "Answers “what does jelly wobble do?” and keeps a conversation"]
        case .localModel: ["What Apple Intelligence does, on Intel Macs, older macOS or where it isn't offered",
                           "Not in this build: open models of 0.5–1.7B parameters scored 3–13 of 30 in our tests, worse than the semantic model"]
        }
    }
    var badge: String {
        switch self {
        case .semantic: "Semantic model"
        case .voice: "Voice"
        case .appleIntelligence: "Apple Intelligence"
        case .localModel: "Local model"
        }
    }
}

/// Where a layer stands on this Mac.
enum LayerStatus: Equatable {
    case ready
    case needsPermission(String)          // button title
    case needsDownload(String)            // in-app download
    case needsSettings(String, URL)       // something to turn on in System Settings
    case downloading(String)
    case unavailable(String)
    case planned

    var label: String {
        switch self {
        case .ready: "Ready"
        case .needsPermission: "Needs permission"
        case .needsDownload: "Download needed"
        case .needsSettings: "Needs setup"
        case .downloading: "Downloading…"
        case .unavailable: "Not available"
        case .planned: "Coming later"
        }
    }
    var color: Color {
        switch self {
        case .ready: .green
        case .needsPermission, .needsDownload, .needsSettings: .orange
        case .downloading: .blue
        case .unavailable, .planned: .gray
        }
    }
}

/// Which layers are on, and what each can do right now. Main-thread only.
final class AILayers: ObservableObject {
    static let shared = AILayers()
    private let d = UserDefaults.standard
    private static let offKey = "aiLayersOff"

    @Published private(set) var off: Set<AILayer>
    @Published private(set) var status: [AILayer: LayerStatus] = [:]

    private init() {
        off = Set((UserDefaults.standard.stringArray(forKey: Self.offKey) ?? []).compactMap(AILayer.init))
        refresh()
    }

    func isOn(_ l: AILayer) -> Bool { l == .semantic || !off.contains(l) }
    func setOn(_ l: AILayer, _ on: Bool) {
        if on { off.remove(l) } else { off.insert(l) }
        d.set(off.map(\.rawValue), forKey: Self.offKey)
    }
    /// On and ready to use.
    func usable(_ l: AILayer) -> Bool { isOn(l) && status[l] == .ready }

    func refresh() {
        let semantic = SemanticModel.shared
        status[.semantic] = semantic.failure.map { .unavailable($0) } ?? (semantic.ready ? .ready : .downloading("Loading…"))
        if !semantic.ready, semantic.failure == nil { semantic.load { [weak self] in self?.refresh() } }
        status[.voice] = ConfigVoice.status
        status[.appleIntelligence] = AppleModel.status
        status[.localModel] = .planned
    }

    /// The layer's button: download, ask for a permission, or open System Settings.
    func act(_ l: AILayer) {
        switch (l, status[l]) {
        case (.voice, .needsPermission?):
            ConfigVoice.requestPermissions { [weak self] _ in self?.refresh() }
        case (_, .needsSettings(_, let url)?):
            NSWorkspace.shared.open(url)
        default: break
        }
    }
}

// MARK: Apple Intelligence

/// Layer 4: Apple's on-device model with guided generation. It answers with a typed plan — a reply and a list of
/// (setting id, value) — and the values go through the same rules as typed commands, so it can't set anything the
/// schema doesn't allow.
enum AppleModel {
    struct Plan {
        let reply: String
        let changes: [(setting: String, value: String)]
        let shortcuts: [(action: String, keys: String, target: String)]
    }

    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!

    static var status: LayerStatus {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *) else { return .unavailable("Needs macOS 26 or later.") }
        switch SystemLanguageModel.default.availability {
        case .available: return .ready
        case .unavailable(.appleIntelligenceNotEnabled):
            return .needsSettings("Turn on Apple Intelligence", settingsURL)
        case .unavailable(.modelNotReady): return .downloading("macOS is still downloading Apple Intelligence.")
        case .unavailable(.deviceNotEligible): return .unavailable("This Mac can't run Apple Intelligence.")
        case .unavailable: return .unavailable("Apple Intelligence isn't available right now.")
        }
        #else
        return .unavailable("This build of Learn was made without Apple Intelligence.")
        #endif
    }

    private static func madeShortcuts() -> String {
        let all = Bindings.shared.scopes.flatMap { Bindings.shared.all($0) }
        return all.isEmpty ? "none." : all.map { "\($0.shortcut.display) → \($0.path.joined(separator: " › "))" }.joined(separator: "; ") + "."
    }

    static func plan(_ text: String, context: [String]) async throws -> Plan? {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *) else { return nil }
        let session = LanguageModelSession(instructions: instructions())
        var prompt = ""
        if !context.isEmpty { prompt += "Earlier in this chat:\n" + context.joined(separator: "\n") + "\n\n" }
        prompt += "The user says: \(text)"
        let plan = try await session.respond(to: prompt, generating: ConfigPlan.self).content
        return Plan(reply: plan.reply, changes: plan.changes.map { ($0.setting, $0.value) },
                    shortcuts: plan.shortcuts.map { ($0.action, $0.keys, $0.target) })
        #else
        return nil
        #endif
    }

    private static func instructions() -> String {
        let rows = ConfigSchema.all.map { s -> String in
            let kind: String
            switch s.kind {
            case .toggle: kind = "on/off"
            case .number(let r, _, let unit):
                kind = unit == .percent ? "percent \(Int(r.lowerBound * 100))–\(Int(r.upperBound * 100))%, or more/less"
                    : "number \(Int(r.lowerBound))–\(Int(r.upperBound)) \(unit == .points ? "pt" : "min"), or more/less"
            case .choice(let o): kind = "one of: " + o.prefix(12).map(\.title).joined(separator: ", ") + (o.count > 12 ? ", …" : "")
            case .color: kind = "a color name or #RRGGBB"
            }
            return "- \(s.id) (\(s.title)): \(s.detail) Value: \(kind). Now: \(s.format(s.get()))."
        }
        return """
        You are the settings assistant inside Learn, a Mac app that searches and runs menu shortcuts and on-screen items. \
        The user tells you how they want Learn to look or behave. Pick the settings that do it and their new values. \
        Only use the settings below. If nothing fits, change nothing and say so kindly. If they ask a question, answer it \
        from the descriptions. Keep replies short and warm, one or two sentences, plain words, no markdown.

        Settings:
        \(rows.joined(separator: "\n"))

        Keyboard shortcuts: the user can also ask Learn to make a shortcut (keys that open an app or website, run one of \
        Learn's commands, or press a menu item in an app) or to remove one they made. Put those in `shortcuts`, not in \
        `changes`. Shortcuts they made: \(Self.madeShortcuts())
        """
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
struct ConfigPlan {
    @Guide(description: "A short, friendly reply in one or two sentences: what you changed, or the answer to the question.")
    var reply: String
    @Guide(description: "Settings to change. Empty when the user only asked something or nothing fits.")
    var changes: [ConfigPlanChange]
    @Guide(description: "Keyboard shortcuts to make or remove. Empty unless the user talks about shortcuts or keys to press.")
    var shortcuts: [ConfigPlanShortcut]
}

@available(macOS 26, *)
@Generable
struct ConfigPlanShortcut {
    @Guide(description: "Make a new shortcut, or remove one the user made.", .anyOf(["create", "remove"]))
    var action: String
    @Guide(description: "The keys, written like “command shift K” or “control option S”. Empty when removing by name or the last one made.")
    var keys: String
    @Guide(description: "What it does, in a few words: “open Safari”, “open github.com”, “label clickable items”, “Reopen Closed Tab in Google Chrome”. For removing: which one, or empty for the one just made.")
    var target: String
}

@available(macOS 26, *)
@Generable
struct ConfigPlanChange {
    @Guide(description: "The id of the setting to change.", .anyOf(ConfigSchema.all.map(\.id)))
    var setting: String
    @Guide(description: "Its new value: on, off, more, less, reset, a number such as 30% or 20, a color such as purple or #FF8800, or one of the setting's options.")
    var value: String
}
#endif
