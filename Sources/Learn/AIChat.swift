import Foundation

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
    var spoken = false                    // user: said out loud; assistant: its reply was read aloud
    var changes: [AppliedChange] = []
    var suggestions: [String] = []        // buttons: tapping one sends it
    var layer: AILayer? = nil             // which layer understood it
    var note: String? = nil               // small print: what it understood, how sure
    var undone = false
    /// Its next-best meanings, offered if the user undoes it: (sentence, [(button, intent)]).
    var alternatives: (text: String, options: [(chip: String, intent: String)])? = nil
}

/// The AI Config conversation. Every sentence goes to the semantic model, which says what it means (an intent from
/// intents.json) and how sure it is. Sure: do it and say so. Torn between two meanings: ask with two buttons, and
/// learn from the answer. Lost: offer the closest meanings, or hand it to Apple Intelligence when that's on.
/// Main-thread only.
final class AIChat: ObservableObject {
    static let shared = AIChat()

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var thinking = false

    private var layers: AILayers { .shared }
    private var model: SemanticModel { .shared }
    /// The setting talked about last, for "turn it off".
    private var lastSetting: ConfigSetting?
    /// A shortcut half asked for ("make a shortcut for Safari" without keys): the next message can finish it.
    private var pending: (combo: KeyCombo?, target: String)?
    /// Buttons offered for a sentence the model wasn't sure about: tapping one runs that intent on the sentence and
    /// teaches the model the sentence means it.
    private var offers: [String: (intent: String, text: String)] = [:]

    /// How sure is sure (cosine similarity to the closest example), measured on held-out paraphrases:
    /// below `lost` it's usually off-topic; a lead under `tie` over the runner-up is often the wrong one of two.
    private let lost: Float = 0.5, tie: Float = 0.06

    func send(_ raw: String, spoken: Bool = false) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking else { return }
        messages.append(ChatMessage(role: .user, text: text, spoken: spoken))
        layers.refresh()
        if model.ready { return respond(text, spoken: spoken) }
        thinking = true
        model.load { [weak self] in
            self?.thinking = false
            self?.respond(text, spoken: spoken)
        }
    }

    /// The Undo button. If the model had read the sentence wrong, it asks what was meant instead, and learns from the answer.
    func undo(_ id: UUID) {
        guard undoChanges(id), let alt = messages.first(where: { $0.id == id })?.alternatives, !alt.options.isEmpty else { return }
        offers = Dictionary(alt.options.map { ($0.chip, ($0.intent, alt.text)) }, uniquingKeysWith: { a, _ in a })
        messages.append(ChatMessage(role: .assistant, text: "Undone. What did you mean by “\(alt.text)”?",
                                    suggestions: alt.options.map(\.chip), layer: .semantic))
    }

    @discardableResult
    private func undoChanges(_ id: UUID) -> Bool {
        guard let i = messages.firstIndex(where: { $0.id == id }), !messages[i].undone else { return false }
        messages[i].changes.reversed().forEach { $0.undo() }
        messages[i].undone = true
        Sounds.play(.click)
        return true
    }

    func clear() { messages.removeAll(); offers = [:]; ConfigVoice.shared.stopSpeaking() }

    private func reply(_ m: ChatMessage, spoken: Bool) {
        var m = m
        m.spoken = spoken
        messages.append(m)
        if !m.changes.isEmpty { Sounds.play(.click) }
        if spoken { ConfigVoice.shared.speak(Self.speakable(m)) }
    }

    // MARK: Understanding

    fileprivate enum Reading {
        case act(SemanticModel.Match, String, alternatives: [SemanticModel.Match] = [])
        case ask([SemanticModel.Match], String)
        case lost([SemanticModel.Match], String)
    }

    private func respond(_ text: String, spoken: Bool) {
        if let failure = model.failure {
            return reply(ChatMessage(role: .assistant, text: "I can't understand anything right now: \(failure)"), spoken: spoken)
        }
        // A button from a "did you mean": do that, and remember what the sentence meant.
        if let offer = offers[text], let intent = model.intents.first(where: { $0.id == offer.intent }) {
            offers = [:]
            if offer.text != text { model.learn(offer.text, as: offer.intent) }
            var m = execute([.act(SemanticModel.Match(intent: intent, score: 1), offer.text, alternatives: [])])
            m.note = "Learned: “\(offer.text)” means “\(intent.chip)”."
            return reply(m, spoken: spoken)
        }
        offers = [:]
        let waiting = pending
        pending = nil
        if let p = waiting, let intent = complete(p, with: text) { return reply(shortcut(intent), spoken: spoken) }

        let readings = ConfigText.sentences(text).flatMap(read)
        let unsure = readings.contains { !$0.isAct }
        guard unsure, layers.usable(.appleIntelligence) else { return reply(execute(readings), spoken: spoken) }

        // Not sure of all of it: ask Apple Intelligence, and fall back to what the model understood.
        thinking = true
        let context = messages.suffix(7).dropLast().map { ($0.role == .user ? "User: " : "Learn: ") + $0.text }
        Task { @MainActor in
            defer { thinking = false }
            do {
                if let plan = try await AppleModel.plan(text, context: Array(context)) { return reply(apply(plan), spoken: spoken) }
            } catch {
                var m = execute(readings)
                m.note = "Apple Intelligence couldn't answer (\(error.localizedDescription))."
                return reply(m, spoken: spoken)
            }
            reply(execute(readings), spoken: spoken)
        }
    }

    /// One sentence → one reading, or one per clause when its parts mean different things
    /// ("the background is nice, but the sound is too loud").
    private func read(_ sentence: String) -> [Reading] {
        // Keys in the sentence: it's about shortcuts, whatever else it says.
        if ConfigShortcuts.combo(in: sentence) != nil {
            let r = model.rank(sentence) { $0.command?.hasPrefix("shortcut.") == true }
            return r.first.map { [.act($0, sentence, alternatives: Array(r.dropFirst().prefix(2)))] } ?? []
        }
        let whole = reading(sentence, model.rank(sentence))
        let parts = ConfigText.clauses(sentence)
        guard parts.count > 1, whole.isSetting else { return [whole] }
        let each = parts.map { reading($0, model.rank($0)) }.filter { !$0.isKeep }
        return each.contains(where: \.isAct) ? each.filter { !$0.isLost } : [whole]
    }

    private func reading(_ text: String, _ ranked: [SemanticModel.Match]) -> Reading {
        var r = ranked
        // "Turn it off": a sentence without a topic is about the setting talked about last.
        if let s = lastSetting, (r.first?.score ?? 0) < 0.75,
           text.range(of: #"\b(it|that|this|them|those)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            let mine = model.rank(text) { $0.setting == s.id }
            if let top = mine.first, top.score >= 0.45 { r = mine }
        }
        guard let top = r.first, top.score >= lost else { return .lost(Array(r.filter { !$0.intent.chip.isEmpty }.prefix(3)), text) }
        if let second = r.dropFirst().first, top.score - second.score < tie, second.intent.command != "none",
           !second.intent.chip.isEmpty, top.intent.command != "hello" {
            return .ask([top, second], text)
        }
        return .act(top, text, alternatives: Array(r.dropFirst().filter { !$0.intent.chip.isEmpty && $0.intent.command != "none" }.prefix(3)))
    }

    // MARK: Doing

    private func execute(_ readings: [Reading]) -> ChatMessage {
        var lines: [String] = [], changes: [AppliedChange] = [], chips: [String] = [], notes: [String] = []
        var alternatives: (text: String, options: [(chip: String, intent: String)])?
        for r in readings {
            switch r {
            case .act(let m, let text, let alts):
                let out = act(m.intent, text)
                lines.append(out.text); changes += out.changes; chips += out.suggestions
                if readings.count == 1, !out.changes.isEmpty, m.score < 1 {
                    alternatives = (text, alts.map { ($0.intent.chip, $0.intent.id) })
                }
                if m.score < 1 { notes.append("“\(m.intent.chip.isEmpty ? m.intent.id : m.intent.chip)” \(String(format: "%.2f", m.score))") }
            case .ask(let options, let text):
                lines.append(readings.count > 1 ? "For “\(text)”, which did you mean?" : "Which did you mean?")
                for o in options { offers[o.intent.chip] = (o.intent.id, text); chips.append(o.intent.chip) }
                notes.append(options.map { "\($0.intent.chip) \(String(format: "%.2f", $0.score))" }.joined(separator: " vs "))
            case .lost(let near, let text):
                let options = near.filter { $0.intent.command != "none" }
                lines.append("I'm not sure what “\(text)” should change." + (options.isEmpty ? "" : " Is it one of these?"))
                for o in options { offers[o.intent.chip] = (o.intent.id, text); chips.append(o.intent.chip) }
                if let top = near.first { notes.append("closest “\(top.intent.chip)” \(String(format: "%.2f", top.score))") }
            }
        }
        var text = lines.filter { !$0.isEmpty }.joined(separator: " ")
        for w in changes.compactMap(\.warning) { text += " " + w }
        var m = ChatMessage(role: .assistant, text: text.isEmpty ? "Done." : text, changes: changes, suggestions: chips, layer: .semantic,
                            note: notes.isEmpty ? nil : "Understood as " + notes.joined(separator: " · "))
        m.alternatives = alternatives
        return m
    }

    /// Does one intent, with the values (numbers, colors, names, keys) read from its sentence.
    private func act(_ intent: SemanticModel.Intent, _ text: String) -> ConfigShortcuts.Outcome {
        if let command = intent.command {
            switch command {
            case "undo": return .init(text: undoLast())
            case "help": return .init(text: Self.help())
            case "hello": return .init(text: intent.reply)
            case "keep": return .init(text: "Okay, I'll leave that as it is.")
            case "none": return .init(text: "I can only change how Learn looks and works, and its shortcuts. Try “the sound is too loud” or “when I press ⌃⌥S, open Safari”.")
            case "resetAll":
                let changes = ConfigSchema.all.flatMap { ConfigSchema.apply($0, .reset) }
                return .init(text: changes.isEmpty ? "Everything is already at its default." : "Everything is back to its default.", changes: changes)
            default:
                let m = shortcut(ConfigShortcuts.intent(command, text))
                return .init(text: m.text, changes: m.changes, suggestions: m.suggestions)
            }
        }
        guard let id = intent.setting, let s = ConfigSchema.setting(id) else { return .init(text: "") }
        lastSetting = s
        if ConfigText.isQuestion(text) { return .init(text: "\(s.title) is \(s.format(s.get())). \(s.detail)") }
        guard let op = operation(intent, s, text) else {
            let place = s.id == "background" ? "background" : "glass"
            return .init(text: "Which color?", suggestions: ["blue", "purple", "pink", "orange", "green"].map { "Make the \(place) \($0)" })
        }
        let changes = ConfigSchema.apply(s, op)
        if !changes.isEmpty { return .init(text: intent.reply, changes: changes) }
        if case .step(let d) = op { return .init(text: "\(s.title) is already at its \(d > 0 ? "highest" : "lowest") (\(s.format(s.get()))).") }
        return .init(text: "\(s.title) is already \(s.format(s.get())).")
    }

    /// The intent's op, made concrete: a number or option named in the sentence wins over "more"/"change".
    private func operation(_ intent: SemanticModel.Intent, _ s: ConfigSetting, _ text: String) -> ConfigOp? {
        let color = ColorNames.find(in: ConfigText.normalize(text))
        if let n = ConfigText.number(text, for: s) { return .set(.number(n)) }
        if let o = ConfigText.option(text, for: s) { return .set(.choice(o)) }
        switch intent.op ?? "" {
        case "on": return .set(.bool(true))
        case "off": return .set(.bool(false))
        case "more": return .step(1)
        case "less": return .step(-1)
        case "reset": return .reset
        case let op where op.hasPrefix("choice:"): return .set(.choice(String(op.dropFirst(7))))
        case "change": return ConfigText.another(s).map { .set(.choice($0)) }
        case "color":
            guard let color else { return nil }
            return s.id == "background" ? .set(.choice(ConfigText.gradient(near: color, away: false, from: s.get()))) : .set(.color(color))
        case "away":
            if s.id == "background" {
                return (color.map { ConfigText.gradient(near: $0, away: true, from: s.get()) } ?? ConfigText.another(s)).map { .set(.choice($0)) }
            }
            let now: HUDStyle.RGBA? = { if case .color(let c) = s.get() { c } else { nil } }()
            return (color ?? now).map { .set(.color(ColorNames.contrasting($0))) }
        default: return nil
        }
    }

    private func undoLast() -> String {
        guard let last = messages.lastIndex(where: { !$0.changes.isEmpty && !$0.undone }) else { return "There's nothing to undo." }
        let labels = messages[last].changes.map(\.undoLabel)
        undoChanges(messages[last].id)
        return "Undone: " + labels.joined(separator: ", ") + "."
    }

    // MARK: Shortcuts

    private func shortcut(_ intent: ShortcutIntent) -> ChatMessage {
        let o: ConfigShortcuts.Outcome
        switch intent {
        case .list: o = ConfigShortcuts.list()
        case .remove(let what): o = ConfigShortcuts.remove(what)
        case .create(let combo, let words):
            guard !words.isEmpty else {
                pending = (combo, "")
                let ask = combo.map { "What should \($0.display) do? For example “open Safari”, “label clickable items”, or “reload page in Safari”." }
                return ChatMessage(role: .assistant, text: ask ?? "Which keys, and what should they do? For example “when I press ⌃⌥S, open Safari”.", layer: .semantic)
            }
            let (target, options) = ConfigShortcuts.resolve(words)
            guard let target else {
                if let combo { pending = (combo, "") }
                let text = options.isEmpty
                    ? "I couldn't find “\(words)”: it isn't an app, a Learn command, or a menu item Learn has read. For a menu item, name the app too, like “… in Safari”."
                    : "“\(words)” is in more than one app. Which one?"
                return ChatMessage(role: .assistant, text: text, suggestions: options.map { (combo.map { $0.display + " " } ?? "") + $0 }, layer: .semantic)
            }
            guard let combo else {
                pending = (nil, words)
                return ChatMessage(role: .assistant, text: "Which keys should do that (\(target.name))? For example ⌃⌥S.", layer: .semantic)
            }
            o = ConfigShortcuts.create(combo, target)
        }
        return ChatMessage(role: .assistant, text: o.text, changes: o.changes, suggestions: o.suggestions, layer: .semantic)
    }

    /// The missing half of a pending shortcut: the keys, or what they should do.
    private func complete(_ p: (combo: KeyCombo?, target: String), with text: String) -> ShortcutIntent? {
        if p.combo == nil, let c = ConfigShortcuts.combo(in: text) { return .create(c.0, target: p.target) }
        if let c = p.combo, p.target.isEmpty { return .create(c, target: ConfigShortcuts.words(text)) }
        return nil
    }

    // MARK: Apple Intelligence

    private func apply(_ plan: AppleModel.Plan) -> ChatMessage {
        var changes: [AppliedChange] = [], skipped: [String] = []
        for c in plan.changes {
            guard let s = ConfigSchema.setting(c.setting), let op = ConfigText.op(for: s, value: c.value) else {
                skipped.append("\(c.setting) = \(c.value)"); continue
            }
            changes += ConfigSchema.apply(s, op)
        }
        var text = plan.reply, suggestions: [String] = []
        for sc in plan.shortcuts {
            let combo = ConfigShortcuts.combo(in: sc.keys)?.0
            let intent: ShortcutIntent = sc.action == "remove"
                ? .remove(combo.map { .combo($0) } ?? (sc.target.isEmpty ? .latest : .named(ConfigShortcuts.words(sc.target))))
                : .create(combo, target: ConfigShortcuts.words(sc.target))
            let m = shortcut(intent)
            changes += m.changes
            suggestions += m.suggestions
            if m.changes.isEmpty { text += " " + m.text }   // it couldn't: say why
        }
        return ChatMessage(role: .assistant, text: text, changes: changes, suggestions: suggestions, layer: .appleIntelligence,
                           note: skipped.isEmpty ? nil : "Skipped what didn't fit a setting: " + skipped.joined(separator: ", "))
    }

    // MARK: Words

    static func help() -> String {
        let on = AILayer.allCases.filter { AILayers.shared.usable($0) }.map(\.title).joined(separator: ", ")
        return "Tell me what you'd like, in your own words: “the sound is too loud”, “that menu isn't necessary”, “I don't like the green background”, "
            + "“when I press ⌃⌥S, open Safari”, “remove the shortcut I just made”, “undo”. When I'm not sure, I'll ask, and remember your answer. "
            + "Working now: \(on)."
    }

    /// The reply as it should sound: key symbols and arrows in words, and the options when it asks.
    static func speakable(_ m: ChatMessage) -> String {
        var t = m.text
        if !m.suggestions.isEmpty, m.suggestions.count <= 3 { t += " " + m.suggestions.joined(separator: ", or ") + "?" }
        for (glyph, word) in [("→", " to "), ("⌃", "Control "), ("⌥", "Option "), ("⇧", "Shift "), ("⌘", "Command "), (" pt", " points"), ("“", ""), ("”", "")] {
            t = t.replacingOccurrences(of: glyph, with: word)
        }
        return t
    }
}

private extension AIChat.Reading {
    var isAct: Bool { if case .act = self { true } else { false } }
    var isLost: Bool { if case .lost = self { true } else { false } }
    var isKeep: Bool { if case .act(let m, _, _) = self { m.intent.command == "keep" } else { false } }
    var isSetting: Bool { if case .act(let m, _, _) = self { m.intent.setting != nil } else { true } }
}
