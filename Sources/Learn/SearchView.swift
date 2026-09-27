import SwiftUI

/// Spotlight's look (macOS 26), measured off a screen recording: one glass shape that is just the search pill until
/// there are results, then grows downward into the list. No header, buttons, footer or section titles.
private enum Metric {
    static let width: CGFloat = 640
    static let bar: CGFloat = 54
    static let radius: CGFloat = 26
    static let row: CGFloat = 56
    static let inset: CGFloat = 10       // rows (and the selection) sit this far in from the glass edge
    static let maxRows: CGFloat = 7.5    // half a row peeks out: there's more below
    static let window = CGSize(width: 720, height: 520)
}

struct SearchView: View {
    @ObservedObject var model: SearchModel
    @FocusState private var focused: Bool
    @State private var shown = true   // entrance: a quick fade and settle, like Spotlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearance) private var look

    /// Spotlight is just the pill until there's something to list.
    private var expanded: Bool { !model.results.isEmpty || model.recording != nil || !model.trusted }
    private var selected: Hit? { model.selection < model.results.count ? model.results[model.selection] : nil }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: expanded ? Metric.radius : Metric.bar / 2, style: .continuous)
        VStack(spacing: 0) {
            bar
            if expanded {
                Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1).padding(.horizontal, 20)
                results.transition(.opacity)
            }
        }
        .frame(width: Metric.width)
        .clipShape(shape)
        .liquidGlass(in: shape)   // plain Liquid Glass by default, like Spotlight; Settings ▸ Appearance can change it
        .glassRim(shape)
        .shadow(color: .black.opacity(look.shadow * 0.5), radius: 24 * look.shadow, y: 12 * look.shadow)
        .scaleEffect(shown ? 1 : 0.97, anchor: .top)
        .opacity(shown ? 1 : 0)
        .animation(.spring(response: 0.26, dampingFraction: 0.9), value: shown)
        .animation(.spring(response: 0.28, dampingFraction: 0.92), value: expanded)
        .padding(.top, 2)
        .frame(width: Metric.window.width, height: Metric.window.height, alignment: .top)
        .onAppear { focused = true }
        .onChange(of: model.focusTick) { focused = true }
        .onChange(of: model.presentTick) {
            guard !reduceMotion else { return }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { shown = false }
            DispatchQueue.main.async { shown = true }
        }
    }

    // MARK: Search bar

    private var bar: some View {
        HStack(spacing: 14) {
            if model.screenOnly {   // ⇥ + Space: searching only what's on screen
                Image(systemName: "cursorarrow.rays").font(.app(21)).foregroundStyle(.blue)
            } else if let app = model.currentApp {
                Image(nsImage: AppCatalog.icon(app)).resizable().interpolation(.high).frame(width: 26, height: 26)
            } else {
                Image(systemName: "magnifyingglass").font(.app(21)).foregroundStyle(.secondary)
            }
            TextField(model.currentApp.map { model.screenOnly ? "Search on screen in \($0.name)" : "Search \($0.name)" } ?? "Learn Search",
                      text: $model.query)
                .textFieldStyle(.plain)
                .font(.app(26))
                .focused($focused)
                .overlay(alignment: .leading) { completion }
            if model.scanning || model.suggesting && model.results.isEmpty {
                ProgressView().controlSize(.small).transition(.opacity)
            } else if !model.query.isEmpty, let hit = selected {
                HitIcon(hit: hit, app: model.currentApp, size: 26, badge: false).transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: Metric.bar)
        .animation(.easeOut(duration: 0.15), value: model.scanning)
    }

    /// Spotlight's grey tag right after the typed text: "hey  — Siri". Here also one-off notices ("Copied", "Saved").
    @ViewBuilder
    private var completion: some View {
        let label = model.notice ?? (model.query.isEmpty ? nil : selected.map { "— " + HitRow.title($0) })
        if let label {
            HStack(spacing: 3) {
                Text(verbatim: model.query).font(.app(26)).fixedSize().hidden()
                Text(verbatim: label)
                    .font(.app(15)).foregroundStyle(.secondary).lineLimit(1)
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .allowsHitTesting(false)
        }
    }

    // MARK: Results

    private var resultsHeight: CGFloat {
        let rows = min(CGFloat(model.results.count), Metric.maxRows)
        let list = rows > 0 ? rows * Metric.row + 2 * Metric.inset : 0
        return (model.trusted ? 0 : 76) + (model.recording != nil ? max(list, 340) : list)
    }

    private var results: some View {
        VStack(spacing: 0) {
            if !model.trusted { permissionBanner }
            ZStack {
                list
                if let r = model.recording { recorder(r).transition(.opacity) }
            }
            .animation(Theme.snappy, value: model.recording?.id)
        }
        .frame(height: resultsHeight, alignment: .top)
    }

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            IconTile(symbol: "lock.fill", color: .orange, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("Accessibility access needed").font(.app(15, .medium))
                Text("Learn reads menus and runs shortcuts through it.").font(.app(13)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Grant Access") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .glassButton(prominent: true)
            .tint(.orange)
        }
        .padding(.horizontal, 20).frame(height: 76)
    }

    // Rows are identified by element id only (never by index) so filtering/mode changes can't show stale rows.
    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { i, hit in
                        HitRow(hit: hit, app: model.currentApp)
                            .frame(maxWidth: .infinity, minHeight: Metric.row, alignment: .leading)
                            .background {
                                if i == model.selection {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.1))
                                }
                            }
                            .contentShape(Rectangle())
                            .asButton(RowPressStyle(sound: false)) { model.activate(i) }
                            .onHover { inside in if inside { model.hover(i) } }
                    }
                }
                .padding(Metric.inset)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selection) { _, _ in
                if model.selectedByHover { model.selectedByHover = false; return }
                if let id = model.selectedID { proxy.scrollTo(id) }
            }
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
                    if !item.location.isEmpty { Text(HitRow.path(item.location)).font(.app(11.5)).foregroundStyle(.secondary) }
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
                            Keycaps(display: item.display, size: 12, dim: true)
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
}

// MARK: Rows

/// One Spotlight row: 36pt icon, title, grey subtitle, grey detail on the right (keys, where Spotlight shows a date).
private struct HitRow: View {
    let hit: Hit
    let app: AppEntry?   // the app being browsed, if any

    static func path(_ s: String) -> String { s.replacingOccurrences(of: " ▸ ", with: " › ") }

    static func title(_ hit: Hit) -> String {
        switch hit {
        case .shortcut(let s), .global(let s, _): s.title
        case .app(let a): a.name
        case .file(let f): f.name
        case .answer(let a): a.title
        }
    }

    private var subtitle: String? {
        switch hit {
        case .shortcut(let s): s.location.isEmpty ? nil : Self.path(s.location)
        case .global(let s, let a): Self.path(s.location.isEmpty ? a.name : "\(a.name) ▸ \(s.location)")
        case .app: nil
        case .file(let f):
            ([f.lastUsed.map { $0.formatted(date: .numeric, time: .shortened) }, f.folder] as [String?]).compactMap { $0 }.joined(separator: " · ")
        case .answer(let a): a.detail
        }
    }

    private var detail: String? {
        switch hit {
        case .shortcut(let s), .global(let s, _):
            let keys = s.hasKey ? s.display : HitIcon.kind(s).tag
            return s.original != nil ? ["Custom", keys].compactMap { $0 }.joined(separator: " · ") : keys
        case .file(let f): return f.score < 0 ? "Contents" : nil
        case .answer(let a): return a.kind == .define ? "Dictionary" : nil
        case .app: return nil
        }
    }

    var body: some View {
        let define: Bool = if case .answer(let a) = hit, a.kind == .define { true } else { false }
        HStack(alignment: define ? .top : .center, spacing: 14) {
            HitIcon(hit: hit, app: app, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                if case .answer(let a) = hit, a.kind != .define {
                    Text(a.title).font(.app(24, .medium)).textSelection(.enabled).lineLimit(1)
                } else {
                    Text(verbatim: Self.title(hit)).font(.app(17)).lineLimit(1)
                }
                if let subtitle {
                    Text(verbatim: subtitle).font(.app(15)).foregroundStyle(.secondary)
                        .lineLimit(define ? 3 : 1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            if let detail { Text(verbatim: detail).font(.app(15)).foregroundStyle(.secondary).lineLimit(1) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, define ? 8 : 0)
    }
}

/// A hit's icon. Menu commands get Spotlight's treatment: a glyph for the kind of item, badged with its app's icon.
private struct HitIcon: View {
    let hit: Hit
    let app: AppEntry?
    let size: CGFloat
    var badge = true

    /// Symbol + color for items without an app icon, by where they come from.
    static func kind(_ s: Shortcut) -> (symbol: String, color: Color, tag: String?) {
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

    private func image(_ ns: NSImage, _ side: CGFloat) -> some View {
        Image(nsImage: ns).resizable().interpolation(.high).frame(width: side, height: side)
    }

    var body: some View {
        switch hit {
        case .app(let a): image(AppCatalog.icon(a), size)
        case .file(let f): image(f.icon, size)
        case .answer(let a):
            let tile: (String, Color) = switch a.kind {
                case .calc: ("equal", .orange)
                case .convert: ("arrow.left.arrow.right", .teal)
                case .define: ("character.book.closed.fill", .brown)
            }
            IconTile(symbol: tile.0, color: tile.1, size: size * 0.86).frame(width: size, height: size)
        case .shortcut(let s), .global(let s, _):
            let owner: AppEntry? = if case .global(_, let a) = hit { a } else { app }
            if !badge, let owner {
                image(AppCatalog.icon(owner), size)
            } else {
                IconTile(symbol: Self.kind(s).symbol, color: Self.kind(s).color, size: size * 0.86)
                    .frame(width: size, height: size)
                    .overlay(alignment: .bottomTrailing) {
                        if let owner { image(AppCatalog.icon(owner), size * 0.5).offset(x: 3, y: 3) }
                    }
            }
        }
    }
}

private extension View {
    func asButton<S: ButtonStyle>(_ style: S, action: @escaping () -> Void) -> some View {
        Button(action: action) { self }.buttonStyle(style)
    }

}
