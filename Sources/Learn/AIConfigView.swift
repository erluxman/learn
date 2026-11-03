import SwiftUI

/// Settings ▸ AI Config: a chat that changes Learn's settings (type → text back, talk → spoken back), and the
/// Models page listing each layer, what it can do, and what it needs.
struct AIConfigPane: View {
    enum Page: String, CaseIterable { case chat = "Chat", models = "Models" }
    @State private var page = Page.chat
    @ObservedObject private var layers = AILayers.shared

    var body: some View {
        Pane(tab: .ai, form: false) {
            VStack(spacing: 12) {
                HStack {
                    Picker("", selection: $page) { ForEach(Page.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                    Spacer()
                    LayerDots(layers: layers).onTapGesture { page = .models }
                }
                .padding(.horizontal, 28)
                Group {
                    switch page {
                    case .chat: ChatView()
                    case .models: ModelsView(layers: layers)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.bottom, 18)
        }
        .onAppear { layers.refresh(); SemanticModel.shared.load() }
    }
}

/// One dot per layer: lit when it's on and ready.
private struct LayerDots: View {
    @ObservedObject var layers: AILayers
    var body: some View {
        HStack(spacing: 6) {
            ForEach(AILayer.allCases) { l in
                Circle().fill(layers.usable(l) ? l.color : .secondary.opacity(0.25)).frame(width: 8, height: 8)
                    .help("\(l.title): \(layers.isOn(l) ? layers.status[l]?.label ?? "" : "Off")")
            }
            Text("\(AILayer.allCases.filter { layers.usable($0) }.count) of \(AILayer.allCases.count) layers")
                .font(.app(12)).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: Chat

private struct ChatView: View {
    @ObservedObject private var chat = AIChat.shared
    @ObservedObject private var voice = ConfigVoice.shared
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if chat.messages.isEmpty { EmptyChat { send($0, spoken: false) } }
                        ForEach(chat.messages) { m in
                            MessageRow(message: m, send: { send($0, spoken: false) }).id(m.id)
                        }
                        if chat.thinking { TypingDots().id("thinking") }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 28).padding(.vertical, 6)
                }
                .scrollIndicators(.never)
                .onChange(of: chat.messages.count) { withAnimation(Theme.smooth) { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: chat.thinking) { withAnimation(Theme.smooth) { proxy.scrollTo("end", anchor: .bottom) } }
            }
            InputBar(draft: $draft, focused: $focused, send: { send(draft, spoken: false) }, mic: mic)
                .padding(.horizontal, 24)
        }
        .onAppear { focused = true }
        .onChange(of: voice.transcript) { _, t in if voice.listening { draft = t } }
    }

    private func send(_ text: String, spoken: Bool) {
        chat.send(text, spoken: spoken)
        draft = ""
    }

    private func mic() {
        if voice.listening { voice.stop(); return }
        let layers = AILayers.shared
        layers.refresh()
        guard layers.isOn(.voice) else { return chat.send("help") }
        switch layers.status[.voice] {
        case .needsPermission?:
            ConfigVoice.requestPermissions { ok in layers.refresh(); if ok { mic() } }
        case .ready?:
            voice.listen { said in send(said, spoken: true) }
        default:
            layers.act(.voice)   // opens the System Settings pane that fixes it
        }
    }
}

private struct EmptyChat: View {
    let send: (String) -> Void
    private let examples = ["The sound is too loud", "I don't like the green background", "Rounder corners", "Less wobble",
                            "When I press ⌃⌥S, open Safari", "Remove the shortcut I just made", "What's the volume?", "Make it calm and quiet"]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconTile(symbol: "sparkles", color: .indigo, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("What should Learn look or act like?").font(.app(17, .semibold))
                    Text("Type it, or click the mic and say it. Nothing leaves this Mac.").font(.app(13)).foregroundStyle(.secondary)
                }
            }
            FlowChips(items: examples, send: send)
        }
        .padding(.top, 24)
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let send: (String) -> Void
    @ObservedObject private var chat = AIChat.shared

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 80)
                HStack(spacing: 6) {
                    if message.spoken { Image(systemName: "waveform").font(.system(size: 11, weight: .semibold)).opacity(0.8) }
                    Text(message.text).textSelection(.enabled)
                }
                .font(.app(14.5))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            HStack(alignment: .top, spacing: 10) {
                IconTile(symbol: message.layer?.symbol ?? "sparkles", color: message.layer?.color ?? .indigo, size: 28)
                VStack(alignment: .leading, spacing: 8) {
                    Text(message.text).font(.app(14.5)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if !message.changes.isEmpty { changes }
                    if !message.suggestions.isEmpty { FlowChips(items: message.suggestions, send: send) }
                    footer
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.1)))
                Spacer(minLength: 60)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var changes: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(message.changes) { c in
                HStack(spacing: 8) {
                    Image(systemName: message.undone ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                        .foregroundStyle(message.undone ? Color.secondary : Color.green)
                    Text(c.label).font(.app(13)).strikethrough(message.undone).foregroundStyle(message.undone ? .secondary : .primary)
                    Spacer(minLength: 0)
                    Button { SettingsWindow.shared.show(c.tab) } label: { Image(systemName: "arrow.up.forward").font(.system(size: 10, weight: .semibold)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Open \(c.tab.title)")
                }
            }
            if !message.undone {
                Button("Undo") { withAnimation(Theme.smooth) { chat.undo(message.id) } }.glassButton().padding(.top, 2)
            }
        }
        .padding(10)
        .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder private var footer: some View {
        if let l = message.layer {
            HStack(spacing: 5) {
                Image(systemName: l.symbol)
                Text(l.badge)
                if message.spoken { Text("· spoken") }
                if let note = message.note { Text("· " + note).lineLimit(2) }
            }
            .font(.app(11)).foregroundStyle(.secondary)
        } else if let note = message.note {
            Text(note).font(.app(11)).foregroundStyle(.secondary)
        }
    }
}

/// Tappable commands that wrap onto new lines.
private struct FlowChips: View {
    let items: [String]
    let send: (String) -> Void
    var body: some View {
        Flow(spacing: 8) {
            ForEach(items, id: \.self) { s in
                Button(s) { send(s) }
                    .buttonStyle(.plain)
                    .font(.app(13, .medium))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.white.opacity(0.1), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
                    .contentShape(Capsule())
            }
        }
    }
}

private struct Flow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [(items: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var items: [Int] = [], x: CGFloat = 0, y: CGFloat = 0, h: CGFloat = 0
        for (i, v) in subviews.enumerated() {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width {
                rows.append((items, y, x - spacing, h)); y += h + spacing; items = []; x = 0; h = 0
            }
            items.append(i); x += s.width + spacing; h = max(h, s.height)
        }
        if !items.isEmpty { rows.append((items, y, x - spacing, h)) }
        return rows
    }
}

private struct TypingDots: View {
    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: AILayer.appleIntelligence.symbol, color: .purple, size: 28)
            TimelineView(.animation) { t in
                HStack(spacing: 5) {
                    ForEach(0..<3) { i in
                        Circle().frame(width: 7, height: 7)
                            .opacity(0.35 + 0.65 * max(0, sin(t.date.timeIntervalSinceReferenceDate * 5 - Double(i) * 0.7)))
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(.white.opacity(0.08), in: Capsule())
            Text(SemanticModel.shared.ready ? "Apple Intelligence is thinking…" : "Loading the semantic model…").font(.app(12)).foregroundStyle(.secondary)
        }
    }
}

private struct InputBar: View {
    @SwiftUI.Binding var draft: String
    var focused: FocusState<Bool>.Binding
    let send: () -> Void
    let mic: () -> Void
    @ObservedObject private var voice = ConfigVoice.shared
    @ObservedObject private var chat = AIChat.shared

    var body: some View {
        HStack(spacing: 10) {
            TextField(voice.listening ? "Listening…" : "Tell Learn what to change…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.app(15))
                .lineLimit(1...4)
                .focused(focused)
                .onSubmit(send)
                .disabled(voice.listening)
            if voice.speaking {
                Button { voice.stopSpeaking() } label: { Image(systemName: "speaker.slash.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Stop talking")
            }
            Button(action: mic) {
                ZStack {
                    if voice.listening {
                        Circle().fill(Color.red.opacity(0.25)).scaleEffect(1 + voice.level * 0.9)
                            .animation(.easeOut(duration: 0.12), value: voice.level)
                    }
                    Circle().fill(voice.listening ? Color.red : Color.white.opacity(0.12))
                    Image(systemName: voice.listening ? "stop.fill" : "mic.fill").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(voice.listening ? .white : .primary)
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .help(voice.listening ? "Stop listening" : "Talk to Learn (it talks back)")
            Button(action: send) {
                Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(draft.isEmpty || chat.thinking ? Color.secondary.opacity(0.3) : Color.indigo))
            }
            .buttonStyle(.plain)
            .disabled(draft.isEmpty || chat.thinking)
        }
        .padding(.leading, 18).padding(.trailing, 7).padding(.vertical, 7)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(voice.listening ? 0.35 : 0.14)))
    }
}

// MARK: Models

private struct ModelsView: View {
    @ObservedObject var layers: AILayers
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Every layer runs on this Mac. Replies in the chat say which layer understood you and how sure it was.",
                      systemImage: "lock.shield.fill")
                    .font(.app(13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(AILayer.allCases) { LayerCard(layer: $0, layers: layers) }
            }
            .padding(.horizontal, 28).padding(.bottom, 12)
        }
        .scrollIndicators(.never)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in layers.refresh() }   // downloads, permissions granted elsewhere
    }
}

private struct LayerCard: View {
    let layer: AILayer
    @ObservedObject var layers: AILayers

    var body: some View {
        let status = layers.status[layer] ?? .unavailable("")
        HStack(alignment: .top, spacing: 14) {
            IconTile(symbol: layer.symbol, color: layer.color, size: 44)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(layer.title).font(.app(16, .semibold))
                    Text(status.label).font(.app(11, .semibold)).foregroundStyle(status.color)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(status.color.opacity(0.15), in: Capsule())
                }
                Text(layer.needs).font(.app(12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(layer.abilities, id: \.self) { a in
                        Label(a, systemImage: "checkmark").font(.app(13)).labelStyle(Bullet())
                    }
                }
                if let detail = detail(status) {
                    Text(detail).font(.app(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                actions(status)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: SwiftUI.Binding(get: { layers.isOn(layer) }, set: { layers.setOn(layer, $0); Sounds.play(.click) }))
                .toggleStyle(.switch).labelsHidden()
                .disabled(layer == .semantic || status == .planned)
                .help(layer == .semantic ? "Always on" : "Use this layer")
        }
        .padding(16)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(.white.opacity(0.1)))
        .opacity(layers.isOn(layer) ? 1 : 0.6)
    }

    private func detail(_ s: LayerStatus) -> String? {
        switch s {
        case .downloading(let why), .unavailable(let why): why.isEmpty ? nil : why
        case .ready where layer == .voice: "Speaking with: \(ConfigVoice.voice?.name ?? "the system voice") (\(ConfigVoice.voiceQuality))."
        default: nil
        }
    }

    @ViewBuilder private func actions(_ s: LayerStatus) -> some View {
        HStack(spacing: 8) {
            switch s {
            case .needsPermission(let t), .needsDownload(let t), .needsSettings(let t, _):
                Button(t) { layers.act(layer) }.glassButton(prominent: true)
            case .downloading:
                ProgressView().controlSize(.small)
            default: EmptyView()
            }
            if layer == .voice, s == .ready, ConfigVoice.voice?.quality != .premium {
                Button("Get a better voice…") { NSWorkspace.shared.open(ConfigVoice.voicesURL) }.glassButton()
                    .help("System Settings ▸ Accessibility ▸ Spoken Content ▸ System voice ▸ Manage Voices: download an Enhanced or Premium English voice")
            }
        }
    }

    private struct Bullet: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                configuration.icon.font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                configuration.title.fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
