import SwiftUI
import ServiceManagement

/// Learn ▸ Settings: sidebar of panes, System Settings style.
final class SettingsWindow {
    static let shared = SettingsWindow()
    static let title = "Learn Settings"
    var isFront: Bool { window?.isKeyWindow == true && NSApp.isActive }

    enum Tab: String, Hashable, CaseIterable, Identifiable {
        case permissions, appearance, hotkeys, panel, display, search, advanced, shortcuts
        var id: Self { self }
        var title: String {
            switch self {
            case .permissions: "Permissions"
            case .appearance: "Appearance"
            case .hotkeys: "Hotkeys"
            case .panel: "Learn Panel"
            case .display: "On Screen"
            case .search: "Search"
            case .advanced: "Advanced"
            case .shortcuts: "My Shortcuts"
            }
        }
        var subtitle: String {
            switch self {
            case .permissions: "What Learn needs to read and run shortcuts. Changes apply instantly."
            case .appearance: "The glass Learn is made of — how clear, frosted, colored and lively it is."
            case .hotkeys: "Global keys that work in every app."
            case .panel: "Keys that work while Learn's panel is open."
            case .display: "The shortcut bubble, pointer mode and mouse chords."
            case .search: "What shows up when you type."
            case .advanced: "Shortcut database, scanning and diagnostics."
            case .shortcuts: "Shortcuts you recorded in Learn. They work without touching the apps' own settings."
            }
        }
        var symbol: String {
            switch self {
            case .permissions: "lock.shield.fill"
            case .appearance: "paintbrush.pointed.fill"
            case .hotkeys: "command"
            case .panel: "rectangle.and.text.magnifyingglass"
            case .display: "sparkles.rectangle.stack.fill"
            case .search: "magnifyingglass"
            case .advanced: "wrench.and.screwdriver.fill"
            case .shortcuts: "keyboard.fill"
            }
        }
        var color: Color {
            switch self {
            case .permissions: .blue
            case .appearance: .cyan
            case .hotkeys: .purple
            case .panel: .indigo
            case .display: .pink
            case .search: .teal
            case .advanced: .gray
            case .shortcuts: .orange
            }
        }
    }

    /// Hooks into AppDelegate for actions that live there.
    var rescanRunning: () -> Void = {}
    var scanAll: () -> Void = {}

    private var window: GlassWindow?
    private let selection = TabSelection()

    func show(_ tab: Tab? = nil) {
        if let tab { selection.tab = tab }
        if window == nil {
            let w = GlassWindow(size: NSSize(width: 880, height: 640), minSize: NSSize(width: 760, height: 480))
            w.title = Self.title
            let host = NSHostingView(rootView: AppearanceRoot { SettingsRoot(selection: selection, window: w) })
            host.sizingOptions = []   // the window sets the size; the glass fills it
            w.host(host)
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class TabSelection: ObservableObject { @Published var tab: SettingsWindow.Tab = .permissions }

/// The window's glass: one rounded shape (no system rim), traffic lights, shadow, and the jelly wobble on drag.
private struct SettingsRoot: View {
    @ObservedObject var selection: TabSelection
    let window: GlassWindow
    @Environment(\.appearance) private var look
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: look.radius, style: .continuous)
        SettingsView(selection: selection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(shape)
            .liquidGlass(in: shape)
            .overlay(alignment: .top) { WindowDragArea().frame(height: 40) }   // title strip: the only place that moves the window
            .overlay(alignment: .topLeading) { TrafficLights(window: window).padding(.top, 18).padding(.leading, 20) }
            .background {   // ⌘W closes, like any window
                Button("") { window.close() }.keyboardShortcut("w").opacity(0)
            }
            .shadow(color: .black.opacity(0.6 * look.shadow), radius: 36 * look.shadow, y: 20 * look.shadow)
            .modifier(Jelly(motion: window.motion))
            .padding(JellyMotion.margin)
    }
}

struct SettingsView: View {
    @ObservedObject var selection: TabSelection
    @Environment(\.appearance) private var look

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: selection)
                .frame(width: 236)
                // concentric with the window: inner radius = outer radius − inset
                .overlay(RoundedRectangle(cornerRadius: max(look.radius - 8, 6), style: .continuous).strokeBorder(Theme.hairline))
                .padding(8)
            Group {
                switch selection.tab {
                case .permissions: PermissionsPane()
                case .appearance: AppearancePane()
                case .hotkeys: HotkeysPane()
                case .panel: PanelPane()
                case .display: DisplayPane()
                case .search: SearchPane()
                case .advanced: AdvancedPane()
                case .shortcuts: ShortcutsPane()
                }
            }
            .id(selection.tab)
            .transition(.opacity.combined(with: .offset(y: 8)))
            .animation(Theme.smooth, value: selection.tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }
}

/// Sidebar: rows light up under the pointer; the selection is a pill of the section's color that flows between rows.
private struct Sidebar: View {
    @ObservedObject var selection: TabSelection
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(SettingsWindow.Tab.allCases) { t in
                SidebarRow(tab: t, selected: selection.tab == t) { selection.tab = t }
                    .anchorPreference(key: SelectionAnchor.self, value: .bounds) { selection.tab == t ? $0 : nil }
            }
            Spacer()
        }
        .backgroundPreferenceValue(SelectionAnchor.self) { anchor in
            GeometryReader { g in if let anchor { LiquidBlob(target: g[anchor], tint: selection.tab.color) } }
        }
        .padding(.top, 44).padding(.horizontal, 10).padding(.bottom, 12)
    }
}

private struct SidebarRow: View {
    let tab: SettingsWindow.Tab
    let selected: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
        Button(action: action) {
            HStack(spacing: 11) {
                IconTile(symbol: tab.symbol, color: tab.color, size: 30)
                    .scaleEffect(hover && !selected ? 1.08 : 1)
                    .rotationEffect(.degrees(hover && !selected ? -4 : 0))
                Text(tab.title).font(.app(14, selected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(shape.fill(Theme.highlight.opacity(hover && !selected ? 0.6 : 0)))
            .pointerLight(shape, strength: 0.7, radius: 110)
            .contentShape(shape)
        }
        .buttonStyle(RowPressStyle())
        .onHover { h in withAnimation(Theme.bouncy) { hover = h } }
    }
}

// MARK: Building blocks

/// Page for one sidebar item: hero (tile, title, blurb) above a grouped form.
private struct Pane<Content: View>: View {
    let tab: SettingsWindow.Tab
    @ViewBuilder let content: Content
    var body: some View {
        Form {
            Section {} header: {
                HStack(spacing: 8) {
                    HeroIcon(symbol: tab.symbol, color: tab.color, size: 64).padding(-16)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tab.title).font(.app(26, .bold))
                        Text(tab.subtitle).font(.app(13)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .textCase(nil)
                .foregroundStyle(.primary)
                .padding(.bottom, 4)
            }
            content
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(alignment: .top) {   // the section's color washes in from the top, like light through tinted glass
            LinearGradient(colors: [tab.color.opacity(0.16), tab.color.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 280)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

/// Settings row: small tile, title, optional explanation, control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    var symbol: String? = nil
    var color: Color = .gray
    @ViewBuilder let control: Control
    @State private var hover = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
        LabeledContent {
            control
        } label: {
            HStack(spacing: 12) {
                if let symbol { IconTile(symbol: symbol, color: color, size: 32).scaleEffect(hover ? 1.06 : 1) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.app(13.5, .medium))
                    if let detail {
                        Text(detail).font(.app(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 8)
        .background(shape.fill(Theme.highlight.opacity(hover ? 0.5 : 0)))
        .pointerLight(shape, strength: 0.6, radius: 180)
        .padding(.horizontal, -8)   // the highlight reaches the card's edge
        .onHover { h in withAnimation(Theme.bouncy) { hover = h } }
    }
}

extension SettingRow where Control == EmptyView {
    init(title: String, detail: String? = nil, symbol: String? = nil, color: Color = .gray) {
        self.init(title: title, detail: detail, symbol: symbol, color: color) { EmptyView() }
    }
}

/// Toggle row with a tile.
private struct ToggleRow: View {
    let title: String
    var detail: String? = nil
    let symbol: String
    let color: Color
    @SwiftUI.Binding var isOn: Bool
    var body: some View {
        SettingRow(title: title, detail: detail, symbol: symbol, color: color) {
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden()
        }
    }
}

/// Resets a key to its default; keeps its space when there's nothing to reset so rows stay aligned.
private struct ResetButton: View {
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward").font(.system(size: 10.5, weight: .semibold)).frame(width: 26, height: 26)
        }
            .buttonStyle(LiquidButtonStyle(shape: Circle()))
            .foregroundStyle(.secondary)
            .help("Reset to default")
            .opacity(disabled ? 0 : 1)
            .disabled(disabled)
    }
}

private struct Note: View {
    let text: String
    var symbol = "info.circle"
    var color: Color = .secondary
    var body: some View {
        Label(text, systemImage: symbol).font(.app(11.5)).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Permissions

private struct PermissionsPane: View {
    @State private var ax = AXIsProcessTrusted()
    @State private var post = CGPreflightPostEventAccess()
    @State private var listen = CGPreflightListenEventAccess()
    @State private var login = SMAppService.mainApp.status == .enabled
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var missing: Int { [ax, post, listen].filter { !$0 }.count }

    var body: some View {
        Pane(tab: .permissions) {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: missing == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.app(26)).foregroundStyle(missing == 0 ? Color.green : Color.orange)
                        .contentTransition(.symbolEffect(.replace))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(missing == 0 ? "All set" : "\(missing) permission\(missing == 1 ? "" : "s") missing")
                            .font(.app(15, .semibold))
                        Text(missing == 0 ? "Learn can read menus, run shortcuts and see your keys."
                                          : "Grant the ones below — no restart needed.")
                            .font(.app(11.5)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .animation(Theme.smooth, value: missing)

                PermissionRow(title: "Accessibility", granted: ax, symbol: "accessibility", color: .blue,
                              detail: "Read menus and on-screen items, click, focus fields, run shortcuts.") {
                    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(opts)
                    openPane("Privacy_Accessibility")
                }
                PermissionRow(title: "Send keystrokes & clicks", granted: post, symbol: "cursorarrow.click.2", color: .indigo,
                              detail: "Real clicks for web apps, right-click menus, key fallbacks.") {
                    _ = CGRequestPostEventAccess(); openPane("Privacy_Accessibility")
                }
                PermissionRow(title: "Input Monitoring", granted: listen, symbol: "keyboard.badge.eye", color: .teal,
                              detail: "Catch your custom shortcuts and label keys in every app.") {
                    _ = CGRequestListenEventAccess(); openPane("Privacy_ListenEvent")
                }
                ToggleRow(title: "Launch at login",
                          detail: "Start Learn automatically so \(Prefs.shared.panelKey.shortcut.display) always works.",
                          symbol: "power", color: .green,
                          isOn: SwiftUI.Binding(get: { login }, set: { on in
                              let svc = SMAppService.mainApp
                              try? on ? svc.register() : svc.unregister()
                              login = svc.status == .enabled
                          }))
                Note(text: "If a permission stays off after granting, remove Learn from that list in System Settings and add it again.")
            }
        }
        .onReceive(tick) { _ in
            ax = AXIsProcessTrusted(); post = CGPreflightPostEventAccess(); listen = CGPreflightListenEventAccess()
            login = SMAppService.mainApp.status == .enabled
        }
    }

    private func openPane(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }
}

private struct PermissionRow: View {
    let title: String, granted: Bool, symbol: String, color: Color, detail: String
    let action: () -> Void
    var body: some View {
        SettingRow(title: title, detail: detail, symbol: symbol, color: color) {
            Group {
                if granted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .font(.app(12, .medium)).foregroundStyle(.green)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                } else {
                    Button("Grant…", action: action).glassButton(prominent: true)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .animation(Theme.bouncy, value: granted)
        }
    }
}

// MARK: Appearance

private struct AppearancePane: View {
    private static let families = NSFontManager.shared.availableFontFamilies
    @ObservedObject private var prefs = Prefs.shared
    private var look: SwiftUI.Binding<Appearance> { $prefs.appearance }

    var body: some View {
        Pane(tab: .appearance) {
            Section("Glass") {
                SettingRow(title: "Blur", detail: "Clear shows more of what's behind; regular is frostier and easier to read.",
                           symbol: "circle.lefthalf.filled", color: .cyan) {
                    Picker("", selection: look.material) {
                        Text("Clear").tag(Appearance.Material.clear)
                        Text("Regular").tag(Appearance.Material.regular)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                slider("Darkness", "Smoke the glass itself — no layer underneath.", "moon.fill", .indigo, look.darkness, 0...1, percent: true)
                SettingRow(title: "Tint", detail: "Color the glass everywhere in Learn.", symbol: "paintpalette.fill", color: .pink) {
                    ColorPicker("", selection: SwiftUI.Binding(get: { prefs.appearance.tintColor },
                                                               set: { prefs.appearance.tint = HUDStyle.RGBA(NSColor($0)) }),
                                supportsOpacity: false)
                        .labelsHidden()
                }
                slider("Tint strength", "0 keeps the glass neutral.", "drop.fill", .purple, look.tintStrength, 0...1, percent: true)
            }
            Section("Type") {
                SettingRow(title: "App font", detail: "Used for all of Learn's text. The on-screen bubble has its own font in On Screen.",
                           symbol: "textformat", color: .orange) {
                    Picker("", selection: SwiftUI.Binding(get: { prefs.appearance.font }, set: { prefs.appearance.fontChoice = $0 })) {
                        Text("SF Pro").tag("")
                        Text("SF Rounded").tag(".rounded")
                        Text("New York").tag(".serif")
                        Text("SF Mono").tag(".mono")
                        Divider()
                        ForEach(Self.families, id: \.self) { Text($0).font(.custom($0, size: 13)).tag($0) }
                    }
                    .labelsHidden().frame(width: 200)
                }
                Text("The quick brown fox jumps over the lazy dog — ⌘⇧N  File › New Folder")
                    .font(.app(15, .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            Section("Icons") {
                SettingRow(title: "Icon style", detail: "Apple's SF Symbols, drawn quiet, neutral or in full color.",
                           symbol: "square.grid.2x2.fill", color: .blue) {
                    Picker("", selection: SwiftUI.Binding(get: { prefs.appearance.iconStyle }, set: { prefs.appearance.iconStyleChoice = $0 })) {
                        Text("Tinted").tag(Appearance.IconStyle.tinted)
                        Text("Mono").tag(Appearance.IconStyle.mono)
                        Text("Color").tag(Appearance.IconStyle.color)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
            Section("Shape") {
                slider("Corner roundness", nil, "app.fill", .orange, look.cornerRadius, 10...40, format: "%.0f pt")
                slider("Shadow", "How far the glass seems to float.", "shadow", .gray, look.shadow, 0...1, percent: true)
            }
            Section("Light & motion") {
                slider("Pointer light", "How much the glass glows and its rim shines under the pointer.",
                       "light.max", .yellow, look.light, 0...2, percent: true)
                slider("Jelly wobble", "How much windows wobble when you drag them. 0 turns it off.",
                       "water.waves", .teal, look.wobble, 0...2, percent: true)
                ToggleRow(title: "Hover motion", detail: "Buttons swell and lean toward the pointer; big icons tilt.",
                          symbol: "cursorarrow.motionlines", color: .green, isOn: look.hoverMotion)
            }
            Section {
                HStack {
                    Spacer()
                    Button("Reset to Defaults") { withAnimation(Theme.smooth) { prefs.appearance = Appearance() } }
                        .glassButton()
                        .disabled(prefs.appearance == Appearance())
                }
            }
        }
    }

    private func slider(_ title: String, _ detail: String?, _ symbol: String, _ color: Color, _ value: SwiftUI.Binding<Double>,
                        _ range: ClosedRange<Double>, percent: Bool = false, format: String = "%.0f") -> some View {
        SettingRow(title: title, detail: detail, symbol: symbol, color: color) {
            HStack(spacing: 10) {
                Slider(value: value, in: range).frame(width: 180)
                Text(percent ? "\(Int((value.wrappedValue * 100).rounded()))%" : String(format: format, value.wrappedValue))
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
            }
        }
    }
}

// MARK: Hotkeys

private struct HotkeysPane: View {
    @ObservedObject private var prefs = Prefs.shared
    @State private var learnKeys = HotkeysPane.currentLearnKeys()
    @State private var spotlight = SpotlightKey.current

    static func currentLearnKeys() -> [[String]: Learn.Binding] {
        Dictionary(Bindings.shared.globals.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private static func look(_ path: [String]) -> (String, Color) {
        switch path {
        case LearnActions.labels: ("tag.fill", .orange)
        case LearnActions.rightClick: ("cursorarrow.click.2", .blue)
        case LearnActions.pointer: ("cursorarrow.motionlines", .green)
        case LearnActions.nextScreen: ("rectangle.2.swap", .teal)
        case LearnActions.settings: ("gearshape.fill", .gray)
        default: ("sparkles", .purple)
        }
    }

    var body: some View {
        Pane(tab: .hotkeys) {
            Section {
                SettingRow(title: "Open Learn", symbol: "magnifyingglass", color: .accentColor) {
                    HStack(spacing: 6) {
                        KeyRecorder(display: prefs.panelKey.shortcut.display) { code, mods in
                            prefs.panelKey = Learn.Binding(path: Prefs.defaultPanelKey.path, keyCode: code, mods: mods)
                        }
                        ResetButton(disabled: prefs.panelKey == Prefs.defaultPanelKey) { prefs.panelKey = Prefs.defaultPanelKey }
                    }
                }
                if !prefs.panelKeyRegistered {
                    Note(text: "\(prefs.panelKey.shortcut.display) is taken by another app or macOS — pick another combo.",
                         symbol: "exclamationmark.triangle.fill", color: .orange)
                }
                SettingRow(title: "⌘Space opens", symbol: "command", color: .purple) {
                    Picker("", selection: SwiftUI.Binding(get: { spotlight }, set: { spotlight = $0; SpotlightKey.apply($0) })) {
                        Text("Spotlight (macOS default)").tag(SpotlightKey.Mode.keep)
                        Text("Learn — Spotlight off").tag(SpotlightKey.Mode.replace)
                        Text("Learn — Spotlight moves to ⌥Space").tag(SpotlightKey.Mode.swap)
                    }
                    .labelsHidden().fixedSize()
                }
                if spotlight != .keep {
                    Note(text: "Learn must be running for ⌘Space to work — keep Launch at login on. Switch back here any time.")
                }
            }
            Section("Learn commands") {
                ForEach(LearnActions.all, id: \.self) { path in
                    let look = Self.look(path)
                    SettingRow(title: path.last ?? "", symbol: look.0, color: look.1) {
                        HStack(spacing: 6) {
                            KeyRecorder(display: learnKeys[path]?.shortcut.display ?? "") { code, mods in
                                Bindings.shared.set(Bindings.global, Learn.Binding(path: path, keyCode: code, mods: mods))
                                learnKeys = HotkeysPane.currentLearnKeys()
                            }
                            ResetButton {
                                Bindings.shared.remove(Bindings.global, path: path)
                                learnKeys = HotkeysPane.currentLearnKeys()
                            }
                        }
                    }
                }
                Note(text: "Any other command or menu item: select it in Learn and press \(prefs.recordKey.shortcut.display).")
            }
        }
    }
}

// MARK: Panel

private struct PanelPane: View {
    @ObservedObject private var prefs = Prefs.shared
    var body: some View {
        Pane(tab: .panel) {
            Section {
                SettingRow(title: "Record a shortcut", detail: "For the selected item.", symbol: "record.circle", color: .red) {
                    HStack(spacing: 6) {
                        KeyRecorder(display: prefs.recordKey.shortcut.display, panelKey: true) { code, mods in
                            prefs.recordKey = Learn.Binding(path: Prefs.defaultRecordKey.path, keyCode: code, mods: mods)
                        }
                        ResetButton(disabled: prefs.recordKey == Prefs.defaultRecordKey) { prefs.recordKey = Prefs.defaultRecordKey }
                    }
                }
                SettingRow(title: "Right-click", detail: "The selected on-screen item.", symbol: "cursorarrow.click.2", color: .blue) {
                    HStack(spacing: 6) {
                        KeyRecorder(display: prefs.contextKey.shortcut.display, panelKey: true) { code, mods in
                            prefs.contextKey = Learn.Binding(path: Prefs.defaultContextKey.path, keyCode: code, mods: mods)
                        }
                        ResetButton(disabled: prefs.contextKey == Prefs.defaultContextKey) { prefs.contextKey = Prefs.defaultContextKey }
                    }
                }
            }
            Section("Built in") {
                ForEach([("↩", "Run the selected item / open the selected app"), ("↑", "Move the selection up"), ("↓", "Move the selection down"),
                         ("⎋", "Back to the app list, then close (or ⌫ on empty search)"), ("⌘R", "Re-read this app's shortcuts"),
                         ("⌘,", "Open these settings"), ("⌘W", "Close Learn")], id: \.1) { key, what in
                    LabeledContent(what) { Keycaps(display: key, size: 11.5) }
                }
            }
        }
    }
}

// MARK: On screen

private struct DisplayPane: View {
    @ObservedObject private var prefs = Prefs.shared
    var body: some View {
        Pane(tab: .display) {
            Section {
                ToggleRow(title: "Show shortcuts as you press them", detail: "A bubble with the keys and the command they run.",
                          symbol: "keyboard.fill", color: .pink, isOn: $prefs.showKeyHUD)
                ToggleRow(title: "Both ⌃ keys = right-click", detail: "Left + right Control together right-clicks at the pointer.",
                          symbol: "contextualmenu.and.cursorarrow", color: .blue, isOn: $prefs.chordRightClick)
                SettingRow(title: "Pointer mode",
                           detail: "\(Bindings.shared.globals.first { $0.path == LearnActions.pointer }?.shortcut.display ?? "Its hotkey"): HJKL or arrows move, ⇧ slow, ⌥ scroll, Space click, D double-click, R right-click, V drag, the hotkey again jumps screens, ⎋ exit.",
                           symbol: "cursorarrow.motionlines", color: .green)
            }
            HUDStyleSections()
        }
    }
}

// MARK: Search

private struct SearchPane: View {
    @ObservedObject private var prefs = Prefs.shared
    var body: some View {
        Pane(tab: .search) {
            Section {
                ToggleRow(title: "On-screen items", detail: "Buttons, fields and links in the front window.",
                          symbol: "cursorarrow.rays", color: .blue, isOn: $prefs.showScreenItems)
                ToggleRow(title: "Menu commands without a shortcut", detail: "Every menu item, not only the ones with keys.",
                          symbol: "filemenu.and.selection", color: .gray, isOn: $prefs.showMenuCommands)
                ToggleRow(title: "Files in your home folder", detail: "Uses the Spotlight index.",
                          symbol: "doc.fill", color: .cyan, isOn: $prefs.searchFiles)
                ToggleRow(title: "Quick answers", detail: "Calculator, conversions (5 km to mi, 100 usd to npr), definitions.",
                          symbol: "equal", color: .orange, isOn: $prefs.quickAnswers)
            }
        }
    }
}

// MARK: Advanced

private struct AdvancedPane: View {
    @ObservedObject private var prefs = Prefs.shared
    var body: some View {
        Pane(tab: .advanced) {
            Section {
                SettingRow(title: "Rescan an app when used", detail: "If its shortcuts are older than this.",
                           symbol: "arrow.clockwise", color: .blue) {
                    Stepper("\(prefs.rescanMinutes) min", value: $prefs.rescanMinutes, in: 1...240).monospacedDigit()
                }
                SettingRow(title: "Shortcut database", symbol: "cylinder.split.1x2.fill", color: .indigo) {
                    HStack(spacing: 8) {
                        Button("Rescan Running") { SettingsWindow.shared.rescanRunning() }
                        Button("Scan All…") { SettingsWindow.shared.scanAll() }
                        Button { NSWorkspace.shared.activateFileViewerSelecting([ShortcutStore.shared.dir]) } label: {
                            Image(systemName: "folder")
                        }.help("Show in Finder")
                    }
                    .glassButton()
                }
            }
            Section("Troubleshooting") {
                ToggleRow(title: "Write debug log", symbol: "ladybug.fill", color: .red, isOn: $prefs.debugLog)
                if prefs.debugLog {
                    Button("Show Log") {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [ShortcutStore.shared.dir.deletingLastPathComponent().appendingPathComponent("debug.log")])
                    }
                    .glassButton()
                }
            }
        }
    }
}

// MARK: My shortcuts

private struct ShortcutsPane: View {
    @State private var groups: [(scope: String, name: String, items: [Learn.Binding])] = []

    var body: some View {
        Pane(tab: .shortcuts) {
            if groups.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "keyboard").font(.system(size: 34, weight: .light)).foregroundStyle(.tertiary)
                        Text("No custom shortcuts yet").font(.app(14, .semibold))
                        HStack(spacing: 5) {
                            Text("Open Learn, select any item, press")
                            Keycaps(display: Prefs.shared.recordKey.shortcut.display, size: 11)
                        }
                        .font(.app(12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 28)
                }
            }
            ForEach(groups, id: \.scope) { g in
                Section {
                    ForEach(g.items, id: \.self) { b in
                        HStack(spacing: 10) {
                            Text(b.path.first == ElementScanner.marker ? "On screen › " + b.path.dropFirst().joined(separator: " › ")
                                                                      : b.path.joined(separator: " › "))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            if let orig = appShortcut(g.scope, b.path) {
                                Text("replaces \(orig)").font(.app(11.5)).foregroundStyle(.secondary)
                            }
                            Keycaps(display: b.shortcut.display, size: 11.5)
                            Button { withAnimation(Theme.snappy) { Bindings.shared.remove(g.scope, path: b.path); reload() } } label: {
                                Image(systemName: "trash").font(.system(size: 11.5)).frame(width: 26, height: 26)
                            }
                            .buttonStyle(LiquidButtonStyle(shape: Circle())).foregroundStyle(.secondary).help("Remove")
                        }
                    }
                } header: {
                    HStack(spacing: 7) {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: g.scope) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
                        } else {
                            IconTile(symbol: "sparkles", color: .purple, size: 18)
                        }
                        Text(g.name)
                    }
                }
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.changed)) { _ in reload() }
    }

    /// The app's own key for this item, if it has one (from Learn's menu database).
    private func appShortcut(_ scope: String, _ path: [String]) -> String? {
        if scope == Bindings.global { return LearnActions.defaults.first { $0.path == path }.map { "default \($0.shortcut.display)" } }
        return ShortcutStore.shared.get(scope)?.shortcuts.first { $0.path == path && $0.hasKey }?.display
    }

    private func reload() {
        groups = Bindings.shared.scopes.compactMap { scope in
            let items = Bindings.shared.all(scope)
            guard !items.isEmpty else { return nil }
            let name = scope == Bindings.global ? "Everywhere (Learn commands)"
                : NSWorkspace.shared.urlForApplication(withBundleIdentifier: scope)
                    .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? scope
            return (scope, name, items)
        }.sorted { $0.name < $1.name }
    }
}

// MARK: Key recorder

/// Click, press a combo (needs ⌘/⌃/⌥ or an F-key); ⎋ cancels.
struct KeyRecorder: View {
    let display: String
    var panelKey = false   // keys used inside Learn's panel may be plain ⇥
    let onRecord: (Int, Mods) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button { recording ? stop() : start() } label: {
            Group {
                if recording {
                    HStack(spacing: 6) {
                        Image(systemName: "record.circle.fill").foregroundStyle(.red).symbolEffect(.pulse)
                        Text("Press keys…").foregroundStyle(.secondary)
                    }
                } else if display.isEmpty {
                    Text("Record").foregroundStyle(.secondary)
                } else {
                    Keycaps(display: display, size: 11.5)
                }
            }
            .font(.app(12, .medium))
            .padding(.horizontal, 8)
            .frame(minWidth: 128, minHeight: 30)
            .fixedSize()
            .overlay { if recording { RecordingRing().transition(.opacity) } }
            .animation(Theme.snappy, value: recording)
            .animation(Theme.bouncy, value: display)
        }
        .buttonStyle(LiquidButtonStyle(shape: Capsule(), tint: recording ? Color.accentColor.opacity(0.35) : nil))
        .help(recording ? "Press a combo · ⎋ cancel" : "Click to record a new shortcut")
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        Recorder.active = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = Recorder.mods(e.modifierFlags)
            if e.keyCode == 53, mods.isEmpty { stop(); return nil }
            if Recorder.acceptable(code: Int(e.keyCode), mods: mods, panelKey: panelKey) {
                onRecord(Int(e.keyCode), mods); stop()
                KeyHUD.shared.flash(Shortcut(path: [], key: Keys.names[Int(e.keyCode)] ?? "", keyCode: Int(e.keyCode), mods: mods).display, caption: "Recorded")
            }
            else { NSSound.beep() }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { recording = false; Recorder.active = false }
    }
}

/// Spinning gradient rim while a recorder listens for keys.
private struct RecordingRing: View {
    @State private var angle = 0.0
    var body: some View {
        Capsule()
            .strokeBorder(AngularGradient(colors: [.accentColor, .purple, .pink, .orange, .accentColor], center: .center,
                                          angle: .degrees(angle)), lineWidth: 1.6)
            .shadow(color: .accentColor.opacity(0.6), radius: 5)
            .onAppear { withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) { angle = 360 } }
    }
}
