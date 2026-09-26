import SwiftUI

struct SearchView: View {
    @ObservedObject var model: SearchModel
    @FocusState private var focused: Bool
    @Namespace private var glass
    @State private var shown = true   // entrance: search bar drops in, results follow a beat later
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearance) private var look

    /// The panel's color: the current app's icon color, else the glass tint, else the accent.
    private var ambient: Color {
        if let app = model.currentApp { return IconColor.of(app) }
        return look.tintStrength > 0 ? look.tintColor : .accentColor
    }

    var body: some View {
        GlassGroup(spacing: 10) {
            VStack(spacing: 10) {
                header
                    .scaleEffect(shown ? 1 : 0.94, anchor: .top)
                    .offset(y: shown ? 0 : -8)
                    .opacity(shown ? 1 : 0)
                    .animation(.spring(response: 0.42, dampingFraction: 0.72), value: shown)
                results
                    .scaleEffect(shown ? 1 : 0.96, anchor: .top)
                    .offset(y: shown ? 0 : -14)
                    .opacity(shown ? 1 : 0)
                    .blur(radius: shown ? 0 : 6)
                    .animation(.spring(response: 0.5, dampingFraction: 0.78).delay(0.05), value: shown)
            }
        }
        .shadow(color: .black.opacity(look.shadow * 0.5), radius: 20 * look.shadow, y: 10 * look.shadow)
        .padding(2)
        .frame(width: 720, height: 480)
        .onAppear { focused = true }
        .onChange(of: model.focusTick) { focused = true }
        .onChange(of: model.presentTick) {
            guard !reduceMotion else { return }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { shown = false }
            DispatchQueue.main.async { shown = true }
        }
    }

    // MARK: Header: search capsule + round buttons

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 12) {
                if let app = model.currentApp {
                    HStack(spacing: 7) {
                        Image(nsImage: AppCatalog.icon(app)).resizable().frame(width: 22, height: 22)
                        Text(app.name).font(.app(13, .semibold)).lineLimit(1)
                    }
                    .padding(.leading, 5).padding(.trailing, 11).padding(.vertical, 5)
                    .background(Theme.highlight, in: Capsule())
                    .transition(.scale(scale: 0.7, anchor: .leading).combined(with: .opacity))
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.app(19, .medium)).foregroundStyle(.secondary)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                TextField(model.currentApp == nil ? "Search apps, shortcuts and files" : "Search \(model.currentApp!.name) shortcuts",
                          text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.app(22, .regular))
                    .focused($focused)
                if model.scanning {
                    ProgressView().controlSize(.small).transition(.opacity)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .liquidGlass(in: Capsule())
            .glassID("search", in: glass)
            .pointerLight(Capsule(), strength: 0.8, radius: 180)

            if model.currentApp != nil {
                roundButton("arrow.clockwise", id: "refresh", help: "Re-read this app's shortcuts (⌘R)", spin: model.scanning) { model.refresh() }
                    .disabled(model.scanning)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
            roundButton("gearshape", id: "settings", help: "Learn Settings (⌘,)") { model.openSettings() }
        }
        .animation(Theme.smooth, value: model.currentApp?.id)
        .animation(Theme.snappy, value: model.scanning)
    }

    private func roundButton(_ symbol: String, id: String, help: String, spin: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.app(17, .medium))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(spin ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: spin)
                .frame(width: 58, height: 58)
        }
        .buttonStyle(LiquidButtonStyle(shape: Circle(), glassID: id, namespace: glass))
        .foregroundStyle(.secondary)
        .help(help)
    }

    // MARK: Results card

    private var results: some View {
        VStack(spacing: 0) {
            if !model.trusted { permissionBanner }
            ZStack {
                list.id(model.currentApp?.id ?? "apps")   // fresh list per mode
                    .transition(.asymmetric(insertion: .move(edge: model.currentApp == nil ? .leading : .trailing).combined(with: .opacity),
                                            removal: .opacity))
                if model.results.isEmpty && !model.scanning { emptyState.transition(.opacity) }
                if let r = model.recording { recorder(r).transition(.opacity) }
            }
            .clipped()
            .animation(Theme.smooth, value: model.currentApp?.id)
            .animation(Theme.snappy, value: model.recording?.id)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            footer
        }
        .frame(maxHeight: .infinity)
        .background(alignment: .top) {   // the app's color washes in from the top, like light through tinted glass
            LinearGradient(colors: [ambient.opacity(0.2), ambient.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 220)
                .allowsHitTesting(false)
                .animation(Theme.smooth, value: model.currentApp?.id)
        }
        .clipShape(RoundedRectangle(cornerRadius: look.radius, style: .continuous))
        .liquidGlass(in: RoundedRectangle(cornerRadius: look.radius, style: .continuous))
        .glassID("results", in: glass)
        .pointerLight(RoundedRectangle(cornerRadius: look.radius, style: .continuous), strength: 0.45, radius: 280)
    }

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            IconTile(symbol: "lock.fill", color: .orange, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Accessibility access needed").font(.app(13, .semibold))
                Text("Learn reads menus and runs shortcuts through it.").font(.app(11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Grant Access") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .glassButton(prominent: true)
            .tint(.orange)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .padding([.horizontal, .top], 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            HeroIcon(symbol: model.query.isEmpty ? "keyboard.fill" : "magnifyingglass", color: ambient, size: 52)
            Text(model.query.isEmpty ? "Nothing here yet" : "No results for “\(model.query)”")
                .font(.app(16, .semibold))
            if model.currentApp != nil {
                Text("Press ⌘R to scan this app again").font(.app(12)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Rows are identified by element id only (never by index) so filtering/mode changes can't show stale rows.
    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { i, hit in
                        let on = i == model.selection
                        let section = self.section(hit)
                        VStack(alignment: .leading, spacing: 1) {
                        if i == 0 || self.section(model.results[i - 1]) != section {
                            Text(section)
                                .font(.app(11.5, .semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 12).padding(.top, i == 0 ? 2 : 12).padding(.bottom, 4)
                        }
                        Group {
                            switch hit {
                            case .shortcut(let s): ShortcutRow(s: s)
                            case .global(let s, let a): ShortcutRow(s: s, app: a)
                            case .app(let a): AppRow(app: a)
                            case .file(let f): FileRow(f: f)
                            case .answer(let a): AnswerRow(a: a)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                        .contentShape(Rectangle())
                        .asButton(RowPressStyle()) { model.activate(i) }
                        .anchorPreference(key: SelectionAnchor.self, value: .bounds) { on ? $0 : nil }
                        .onHover { inside in if inside { model.hover(i) } }
                        }
                    }
                }
                .backgroundPreferenceValue(SelectionAnchor.self) { anchor in
                    GeometryReader { g in if let anchor { LiquidBlob(target: g[anchor], tint: ambient) } }
                }
                .padding(8)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selection) { _, _ in
                if model.selectedByHover { model.selectedByHover = false; return }
                if let id = model.selectedID { withAnimation(Theme.snappy) { proxy.scrollTo(id) } }
            }
        }
    }

    /// Heading a run of results sits under: what kind they are, or the menu they're in while browsing an app.
    private func section(_ hit: Hit) -> String {
        switch hit {
        case .answer: return "Answer"
        case .app: return "Applications"
        case .file: return "Files"
        case .global: return "Shortcuts in other apps"
        case .shortcut(let s):
            if s.path.first == ElementScanner.marker { return "On screen" }
            if s.path.first == LearnActions.group { return "Learn" }
            if !model.query.isEmpty { return "Best matches" }   // ranked, so menus interleave
            if s.path.first == SearchModel.settingsGroup, s.path.count > 2 { return s.path[1] }
            return s.path.count > 1 ? s.path[0] : "Commands"
        }
    }

    // MARK: Recorder

    private func recorder(_ item: Shortcut) -> some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.18))
            VStack(spacing: 16) {
                VStack(spacing: 3) {
                    Text("NEW SHORTCUT FOR").font(.app(10.5, .semibold)).tracking(0.8).foregroundStyle(.secondary)
                    Text(item.title).font(.app(18, .semibold))
                    if !item.location.isEmpty { Text(Row.path(item.location)).font(.app(11.5)).foregroundStyle(.secondary) }
                }
                Group {
                    if let rec = model.recordedShortcut {
                        Keycaps(display: rec.display, size: 22).id(rec.display)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    } else {
                        Text("Press keys…").font(.app(17, .medium)).foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
                .frame(minWidth: 240, minHeight: 64)
                .background(Theme.highlight, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .animation(Theme.bouncy, value: model.recordedShortcut?.display)

                VStack(spacing: 5) {
                    if item.hasKey {
                        HStack(spacing: 6) {
                            Text("Current").font(.app(11.5)).foregroundStyle(.secondary)
                            Keycaps(display: item.display, size: 10, dim: true)
                            if item.isCustom { Text("custom").font(.app(11.5)).foregroundStyle(.secondary) }
                        }
                    }
                    if let c = model.conflicts.first {
                        Label("Already used by \(c.path.joined(separator: " › "))", systemImage: "exclamationmark.triangle.fill")
                            .font(.app(11.5, .medium)).foregroundStyle(.orange)
                    }
                    Text("Works right away in \(model.currentApp?.name ?? "the app") — Learn runs the menu item.")
                        .font(.app(11.5)).foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    KeyHint(keys: "↩", label: "Save")
                    if item.isCustom { KeyHint(keys: "⌫", label: "Remove custom") }
                    KeyHint(keys: "⎋", label: "Cancel")
                }
            }
            .padding(24)
            .frame(width: 440)
            .liquidGlass(in: RoundedRectangle(cornerRadius: look.radius, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Text(model.notice ?? model.info)
                .font(.app(11.5)).foregroundStyle(.secondary).lineLimit(1)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: model.notice)
            Spacer(minLength: 8)
            if model.currentApp == nil {
                KeyHint(keys: "↩", label: "Open")
                KeyHint(keys: "⌘↩", label: "Reveal")
                KeyHint(keys: "⌘,", label: "Settings")
            } else {
                KeyHint(keys: "↩", label: "Run")
                KeyHint(keys: Prefs.shared.recordKey.shortcut.display, label: "Set key")
                KeyHint(keys: Prefs.shared.contextKey.shortcut.display, label: "Right-click")
                KeyHint(keys: "⎋", label: "Back")
            }
        }
        .padding(.horizontal, 16).frame(height: 38)
    }
}

// MARK: Rows

private enum Row {
    static func path(_ s: String) -> String { s.replacingOccurrences(of: " ▸ ", with: " › ") }

    static func title(_ s: String, _ size: CGFloat = 14) -> some View {
        Text(s).font(.app(size, .medium)).lineLimit(1)
    }
    static func subtitle(_ s: String) -> some View {
        Text(s).font(.app(11.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
    }
    static func tag(_ s: String, color: Color = .secondary) -> some View {
        Text(s).font(.app(10.5, .semibold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(color.opacity(0.12), in: Capsule())
    }
    static func icon(_ image: NSImage) -> some View {
        Image(nsImage: image).resizable().interpolation(.high).frame(width: 30, height: 30)
    }
}

private struct AppRow: View {
    let app: AppEntry
    var body: some View {
        HStack(spacing: 12) {
            Row.icon(AppCatalog.icon(app))
            Row.title(app.name, 14.5)
            if app.runningApp != nil {
                Circle().fill(.green.gradient).frame(width: 6, height: 6).help("Running")
            }
            Spacer()
            if let e = ShortcutStore.shared.get(app.id) {
                Text("\(e.shortcuts.count) commands").font(.app(11.5)).foregroundStyle(.tertiary).monospacedDigit()
            }
        }
    }
}

private struct FileRow: View {
    let f: FileHit
    var body: some View {
        HStack(spacing: 12) {
            Row.icon(f.icon)
            VStack(alignment: .leading, spacing: 1) {
                Row.title(f.name)
                Row.subtitle(f.folder)
            }
            Spacer()
            if f.score < 0 { Row.tag("Contents") }
        }
    }
}

private struct AnswerRow: View {
    let a: Answer
    private var tile: (String, Color) {
        switch a.kind {
        case .calc: ("equal", .orange)
        case .convert: ("arrow.left.arrow.right", .teal)
        case .define: ("character.book.closed.fill", .brown)
        }
    }
    var body: some View {
        HStack(alignment: a.kind == .define ? .top : .center, spacing: 12) {
            IconTile(symbol: tile.0, color: tile.1, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.title)
                    .font(.system(size: a.kind == .define ? 15 : 22, weight: .semibold, design: a.kind == .define ? .default : .rounded))
                    .textSelection(.enabled)
                Text(a.detail).font(.app(11.5)).foregroundStyle(.secondary).lineLimit(a.kind == .define ? 3 : 1)
            }
            Spacer()
            if a.kind == .define { Row.tag("Dictionary") } else { KeyHint(keys: "↩", label: "Copy") }
        }
    }
}

private struct ShortcutRow: View {
    let s: Shortcut
    var app: AppEntry? = nil   // another app's shortcut found from anywhere: show its icon and name

    /// Symbol + color for items without an app icon, by where they come from.
    private var kind: (symbol: String, color: Color, tag: String?) {
        switch s.path.first {
        case ElementScanner.marker: ("cursorarrow.rays", .blue, "On screen")
        case LearnActions.group: ("sparkles", .purple, "Learn")
        case SearchModel.settingsGroup:
            switch s.path.dropFirst().first {
            case let tab?: SettingsWindow.Tab.allCases.first { $0.title == tab }.map { ($0.symbol, $0.color, nil) } ?? ("gearshape.fill", .gray, nil)
            default: ("gearshape.fill", .gray, nil)
            }
        case "File": ("doc.fill", .gray, nil)
        case "Edit": ("pencil", .gray, nil)
        case "View": ("eye.fill", .gray, nil)
        case "Window": ("macwindow", .gray, nil)
        case "Help": ("questionmark", .gray, nil)
        case "Format": ("textformat", .gray, nil)
        case "History": ("clock.fill", .gray, nil)
        case "Bookmarks": ("bookmark.fill", .gray, nil)
        default: ("filemenu.and.selection", .gray, nil)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            if let app { Row.icon(AppCatalog.icon(app)) } else { IconTile(symbol: kind.symbol, color: kind.color, size: 26).padding(2) }
            VStack(alignment: .leading, spacing: 1) {
                Row.title(s.title)
                let location = app.map { s.location.isEmpty ? $0.name : "\($0.name) ▸ \(s.location)" } ?? s.location
                if !location.isEmpty { Row.subtitle(Row.path(location)) }
            }
            Spacer(minLength: 8)
            if let orig = s.original {
                Row.tag("Custom", color: .purple).help(orig.isEmpty ? "Set in Learn" : "Set in Learn · app's own: \(orig)")
            }
            if s.hasKey { Keycaps(display: s.display, size: 11.5) }
            else if let tag = kind.tag { Row.tag(tag, color: kind.color) }
        }
    }
}

private extension View {
    func asButton<S: ButtonStyle>(_ style: S, action: @escaping () -> Void) -> some View {
        Button(action: action) { self }.buttonStyle(style)
    }
}
