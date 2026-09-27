import SwiftUI
import ServiceManagement

/// Learn ▸ Settings: sidebar of panes, System Settings style.
final class SettingsWindow {
    static let shared = SettingsWindow()
    static let title = "Learn Settings"
    var isFront: Bool { window?.isKeyWindow == true && NSApp.isActive }

    enum Tab: String, Hashable, CaseIterable, Identifiable {
        case permissions, appearance, hotkeys, display, search, advanced, shortcuts
        var id: Self { self }
        var title: String {
            switch self {
            case .permissions: "General"
            case .appearance: "Appearance"
            case .hotkeys: "Hotkeys"
            case .display: "On Screen"
            case .search: "Search"
            case .advanced: "Advanced"
            case .shortcuts: "My Shortcuts"
            }
        }
        var subtitle: String {
            switch self {
            case .permissions: "Permissions, launch at login, the Cleaner and sounds."
            case .appearance: "The glass Learn is made of — how clear, frosted, colored and lively it is."
            case .hotkeys: "Learn's keys: global ones that work in every app, and the ones inside Learn's panel."
            case .display: "The shortcut bubble, pointer mode and mouse chords."
            case .search: "What shows up when you type."
            case .advanced: "Shortcut database, scanning and diagnostics."
            case .shortcuts: "Shortcuts you recorded in Learn. They work without touching the apps' own settings."
            }
        }
        var symbol: String {
            switch self {
            case .permissions: "gearshape.fill"
            case .appearance: "paintbrush.pointed.fill"
            case .hotkeys: "command"
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
            let w = GlassWindow(size: NSSize(width: 880, height: 640), minSize: NSSize(width: 760, height: 480), margin: 64)
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
            .background { if look.surface != .glass { SettingsBackdrop(tab: selection.tab) } }
            .background(WindowDragArea())   // any empty spot moves the window
            .clipShape(shape)
            .modifier(SurfaceFinish(shape: shape, glass: look.surface == .glass))
            .onAppear { window.appearance = look.surface == .glass ? nil : NSAppearance(named: .darkAqua) }
            .onChange(of: look.surface) { _, s in window.appearance = s == .glass ? nil : NSAppearance(named: .darkAqua) }
            .overlay(alignment: .top) { WindowDragArea().frame(height: 40) }   // title strip: the only place that moves the window
            .overlay(alignment: .topLeading) { TrafficLights(window: window).padding(.top, 18).padding(.leading, 20) }
            .background {   // ⌘W closes, like any window
                Button("") { window.close() }.keyboardShortcut("w").opacity(0)
            }
            .shadow(color: .black.opacity(0.6 * look.shadow), radius: 36 * look.shadow, y: 20 * look.shadow)
            .modifier(Jelly(motion: window.motion))
            .padding(window.margin)
    }
}

/// The Colorful surface: the page's own living gradient (Cleaner-style).
private struct SettingsBackdrop: View {
    let tab: SettingsWindow.Tab
    var body: some View {
        // One surface that changes color in place (Core Animation fades the colors): a crossfade of two surfaces
        // would be half see-through midway, letting the desktop show through.
        SurfaceBackdrop(color: tab.color)
            .allowsHitTesting(false)
    }
}

/// Glass surface (blur, tint and rim from Appearance) or, over a gradient, just a fine light edge.
private struct SurfaceFinish<S: InsettableShape>: ViewModifier {
    let shape: S
    let glass: Bool
    func body(content: Content) -> some View {
        if glass { content.liquidGlass(in: shape).glassRim(shape) }
        else { content.overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.75)) }
    }
}

struct SettingsView: View {
    @ObservedObject var selection: TabSelection
    @Environment(\.appearance) private var look

    var body: some View {
        HStack(spacing: 0) {
            if look.surface == .glass {
                Sidebar(selection: selection)
                    .frame(width: 236)
                    // concentric with the window: inner radius = outer radius − inset
                    .overlay(RoundedRectangle(cornerRadius: max(look.radius - 8, 6), style: .continuous).strokeBorder(Theme.hairline))
                    .padding(8)
            } else {   // on a gradient the sidebar is part of the surface; a hairline that fades at both ends is all that parts it
                Sidebar(selection: selection)
                    .frame(width: 236)
                    .padding(.vertical, 8).padding(.leading, 8)
                    .overlay(alignment: .trailing) {
                        LinearGradient(colors: [.white.opacity(0), .white.opacity(0.13), .white.opacity(0.13), .white.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(width: 1).padding(.vertical, 90)
                    }
            }
            Group {
                switch selection.tab {
                case .permissions: PermissionsPane()
                case .appearance: AppearancePane()
                case .hotkeys: HotkeysPane()
                case .display: DisplayPane()
                case .search: SearchPane()
                case .advanced: AdvancedPane()
                case .shortcuts: ShortcutsPane()
                }
            }
            .id(selection.tab)
            .transition(.blurFade)   // the page frosts over and the next one clears in; the surface stays solid
            .animation(.easeInOut(duration: 0.42), value: selection.tab)   // the Cleaner's timing
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }
}

/// Sidebar: rows light up under the pointer; the selection is a pill of the section's color that flows between rows.
private struct Sidebar: View {
    @ObservedObject var selection: TabSelection
    @Environment(\.appearance) private var look
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(SettingsWindow.Tab.allCases) { t in
                SidebarRow(tab: t, selected: selection.tab == t) { selection.tab = t }
                    .anchorPreference(key: SelectionAnchor.self, value: .bounds) { selection.tab == t ? $0 : nil }
            }
            Spacer()
        }
        .backgroundPreferenceValue(SelectionAnchor.self) { anchor in
            GeometryReader { g in
                if let anchor {
                    if look.surface == .glass { LiquidBlob(target: g[anchor], tint: selection.tab.color) }
                    else { SelectionPill(target: g[anchor]) }
                }
            }
        }
        .padding(.top, 44).padding(.horizontal, 10).padding(.bottom, 12)
    }
}

/// The Cleaner's selection pill (frosted, light top edge), sliding to the selected row on a soft spring.
private struct SelectionPill: View {
    let target: CGRect
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        shape.fill(.white.opacity(0.13))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            .frame(width: target.width, height: target.height)
            .position(x: target.midX, y: target.midY)
            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: target)
    }
}

private struct SidebarRow: View {
    let tab: SettingsWindow.Tab
    let selected: Bool
    let action: () -> Void
    @Environment(\.appearance) private var look
    @State private var hover = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
        Button(action: action) {
            HStack(spacing: 11) {
                icon
                    .animation(Self.morph, value: selected)
                    .keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: selected) { v, s in
                        v.scaleEffect(x: s.width, y: s.height)
                    } keyframes: { _ in
                        // Selected: swell, squash, settle — a small jelly bounce as the color flows in. Deselected: a soft dip.
                        KeyframeTrack(\.width) {
                            if selected {
                                SpringKeyframe(1.2, duration: 0.16, spring: .snappy); SpringKeyframe(0.9, duration: 0.14)
                                SpringKeyframe(1.05, duration: 0.14); SpringKeyframe(1, duration: 0.3, spring: .smooth)
                            } else {
                                SpringKeyframe(0.88, duration: 0.14); SpringKeyframe(1, duration: 0.35, spring: .bouncy)
                            }
                        }
                        KeyframeTrack(\.height) {
                            if selected {
                                SpringKeyframe(1.12, duration: 0.16, spring: .snappy); SpringKeyframe(1.08, duration: 0.14)
                                SpringKeyframe(0.97, duration: 0.14); SpringKeyframe(1, duration: 0.3, spring: .smooth)
                            } else {
                                SpringKeyframe(0.88, duration: 0.14); SpringKeyframe(1, duration: 0.35, spring: .bouncy)
                            }
                        }
                    }
                Text(tab.title).font(.app(14, selected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .contentShape(shape)
            .rowHover()

        }
        .buttonStyle(RowPressStyle())
        .onHover { h in withAnimation(Theme.bouncy) { hover = h } }
    }

    /// The color flow between looks: the Cleaner's 0.42 s, on a spring so it eases in and settles organically.
    static let morph = Animation.spring(duration: 0.45, bounce: 0.15)

    /// Frosted ↔ 3D glass is one icon whose glass changes color (exactly the Cleaner's morph); other style pairs
    /// cross-fade on the same timing.
    @ViewBuilder private var icon: some View {
        if look.idleIconStyle == .frosted && look.iconStyle == .slab {
            GlassSlab(symbol: tab.symbol, color: tab.color, size: 30, frosted: !selected).modifier(IconHover(size: 30))
        } else {
            ZStack {   // other style pairs: the new look blooms out of the old one
                IconTile(symbol: tab.symbol, color: tab.color, size: 30, style: look.idleIconStyle)
                    .opacity(selected ? 0 : 1).scaleEffect(selected ? 0.8 : 1)
                IconTile(symbol: tab.symbol, color: tab.color, size: 30, style: look.iconStyle)
                    .opacity(selected ? 1 : 0).scaleEffect(selected ? 1 : 0.8)
            }
        }
    }
}

// MARK: Building blocks

/// Page for one sidebar item: hero (tile, title, blurb) above a grouped form.
private struct Pane<Content: View>: View {
    let tab: SettingsWindow.Tab
    @ViewBuilder let content: Content
    @Environment(\.appearance) private var look
    var body: some View {
        // The hero stays put so you always know which page you're on; only the form below it scrolls.
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                HeroIcon(symbol: tab.symbol, color: tab.color, size: 84).padding(-20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tab.title).font(.app(26, .bold))
                    Text(tab.subtitle).font(.app(13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .allowsHitTesting(false)   // clicks and scrolls on the text reach the drag area behind
            }
            .padding(.leading, 34).padding(.trailing, 24).padding(.top, 48).padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Behind the header: dragging it moves the window, scrolling on it scrolls the form; the icon keeps its hover.
            .background(WindowDragArea(forwardsScroll: true))
            Form { content }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 20, for: .scrollIndicators)   // keep the scroller clear of the rounded corner
        }
        .background(alignment: .top) {   // on glass, the section's color washes in from the top, like light through tinted glass
            if look.surface == .glass {
                LinearGradient(colors: [tab.color.opacity(0.16), tab.color.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 280)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
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
        // Icon, text and control all centred on one line, so a slider sits level with its title block, not its first baseline.
        HStack(alignment: .center, spacing: 12) {
            if let symbol { IconTile(symbol: symbol, color: color, size: 32) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(13.5, .medium))
                if let detail {
                    Text(detail).font(.app(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control.fixedSize()   // keeps its own width; the text wraps instead
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .contentShape(shape)
        .rowHover()   // anywhere on the row: the row comes forward softly, its icon swells and tilts
        .padding(.horizontal, -4)
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
            Toggle("", isOn: SwiftUI.Binding(get: { isOn }, set: { isOn = $0; Sounds.play(.click) }))
                .toggleStyle(.switch).labelsHidden()
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
    @State private var login = LoginItem.isOn
    @State private var loginError: String?
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
                          detail: loginError ?? (LoginItem.needsApproval
                              ? "Turn Learn on in System Settings ▸ General ▸ Login Items to finish."
                              : "Start Learn automatically so \(Prefs.shared.panelKey.shortcut.display.macKeyWords) always works."),
                          symbol: "power", color: .green,
                          isOn: SwiftUI.Binding(get: { login }, set: { on in
                              loginError = LoginItem.set(on).map { "Couldn't change it: \($0)" }
                              login = LoginItem.isOn
                          }))
                Note(text: "If a permission stays off after granting, remove Learn from that list in System Settings and add it again.")
            }
            Section("Cleaner") {
                SettingRow(title: "Cleaner", detail: "Smart Care, Cleanup, Protection, Performance, Applications and My Clutter, in their own window.",
                           symbol: "sparkles", color: .pink) {
                    Button("Open") { CleanerWindow.shared.show() }.glassButton(prominent: true)
                }
            }
            SoundSection()
        }
        .onReceive(tick) { _ in
            ax = AXIsProcessTrusted(); post = CGPreflightPostEventAccess(); listen = CGPreflightListenEventAccess()
            login = LoginItem.isOn   // follows the menu bar switch and System Settings too
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

// MARK: Cleaner

// MARK: Appearance

private struct AppearancePane: View {
    @ObservedObject private var prefs = Prefs.shared
    private var look: SwiftUI.Binding<Appearance> { $prefs.appearance }

    var body: some View {
        Pane(tab: .appearance) {
            Section {
                SettingRow(title: "Surface", detail: "Colorful gives each page its own living gradient, like the Cleaner. Liquid glass lets the screen show through.",
                           symbol: "rectangle.fill.on.rectangle.angled.fill", color: .pink) {
                    Picker("", selection: SwiftUI.Binding(get: { prefs.appearance.surface }, set: { prefs.appearance.surfaceChoice = $0 })) {
                        ForEach(Appearance.Surface.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 190)
                }
                // Gradients draw their own color; only the glass takes one.
                if prefs.appearance.surface == .glass {
                    SettingRow(title: "Glass color", symbol: "paintpalette.fill", color: .purple) {
                        ColorPicker("", selection: SwiftUI.Binding(get: { prefs.appearance.tintColor },
                                                                   set: { prefs.appearance.tint = HUDStyle.RGBA(NSColor($0)) }),
                                    supportsOpacity: false)
                            .labelsHidden()
                    }
                    slider("Color intensity", "How strongly the glass takes the color. 0 keeps it clear.",
                           "drop.fill", .blue, look.tintStrength, 0...1, percent: true)
                }
            }
            Section("Motion") {
                slider("Jelly wobble", "How much windows wobble when you drag them. 0 turns it off.",
                       "water.waves", .teal, look.wobble, 0...2, percent: true)
            }
            Section {
                HStack {
                    Spacer()
                    Button("Reset to Default") { withAnimation(Theme.smooth) { prefs.appearance = Appearance() } }
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
                Slider(value: value, in: range).sliderTicks(value.wrappedValue, in: range).frame(width: 180)
                Text(percent ? "\(Int((value.wrappedValue * 100).rounded()))%" : String(format: format, value.wrappedValue))
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
            }
        }
    }
}

// MARK: Sounds

/// Volume for Learn's click and shortcut sounds (shown on the General page).
private struct SoundSection: View {
    @ObservedObject private var prefs = Prefs.shared
    var body: some View {
        Section("Sounds") {
            SettingRow(title: "Volume", detail: "Clicks in Learn, and each shortcut it runs for you. 0 is silent.",
                       symbol: "speaker.wave.3.fill", color: .red) {
                HStack(spacing: 10) {
                    Slider(value: SwiftUI.Binding(get: { prefs.appearance.soundVolume }, set: { prefs.appearance.soundVolumeChoice = $0 }),
                           in: 0...1) { editing in if !editing { Sounds.play(.click) } }
                        .sliderTicks(prefs.appearance.soundVolume, in: 0...1)
                        .frame(width: 180)
                    Text("\(Int((prefs.appearance.soundVolume * 100).rounded()))%")
                        .monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                }
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
                    Note(text: "\(prefs.panelKey.shortcut.display.macKeyWords) is taken by another app or macOS — pick another combo.",
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
                Note(text: "Any other command or menu item: select it in Learn and press \(prefs.recordKey.shortcut.display.macKeyWords).")
            }
            PanelSections()
        }
    }
}

// MARK: Panel

/// Keys that work while Learn's panel is open (shown on the Hotkeys page).
private struct PanelSections: View {
    @ObservedObject private var prefs = Prefs.shared
    var body: some View {
        Group {
            Section("In the Learn panel") {
                SettingRow(title: "Record a shortcut", detail: "For the selected item.", symbol: "record.circle", color: .red) {
                    HStack(spacing: 6) {
                        KeyRecorder(display: prefs.recordKey.shortcut.display, panelKey: true) { code, mods in
                            prefs.recordKey = Learn.Binding(path: Prefs.defaultRecordKey.path, keyCode: code, mods: mods)
                        }
                        ResetButton(disabled: prefs.recordKey == Prefs.defaultRecordKey) { prefs.recordKey = Prefs.defaultRecordKey }
                    }
                }
            }
            Section("Built into the panel") {
                ForEach([("↩", "Run the selected item / open the selected app"), ("⇥", "Next item (on an app: show its shortcuts instead of opening it)"), ("⇧⇥", "Previous item"),
                         ("⇥ + Space", "Right-click the highlighted on-screen item"),
                         ("⇥ ", "Nothing typed in an app: search only what's on screen"), ("⇧⇥ ", "Nothing typed in an app: frequently used ↔ suggested"),
                         ("↑", "Move the selection up"), ("↓", "Move the selection down"),
                         ("⎋", "Back to the app list, then close (or delete on empty search)"), ("⌘R", "Full rescan of this app (it also refreshes quietly each time you open it)"),
                         ("⌘,", "Open these settings"), ("⌘W", "Close Learn")], id: \.1) { key, what in
                    HStack(alignment: .center) {
                        Text(what).frame(maxWidth: .infinity, alignment: .leading)
                        Keycaps(display: key, size: 14, room: 1.5)
                    }
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
                           detail: "\(Bindings.shared.globals.first { $0.path == LearnActions.pointer }?.shortcut.display.macKeyWords ?? "Its hotkey"): HJKL or arrows move, shift slow, ⌥ scroll, space click, D double-click, R right-click, V drag, the hotkey again jumps screens, esc exit.",
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
                            Keycaps(display: Prefs.shared.recordKey.shortcut.display, size: 13.5, room: 1.5)
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
                            Keycaps(display: b.shortcut.display, size: 14, room: 1.5)
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
/// The keycaps sit right on the row — no glass capsule — but move like Learn's liquid buttons: they swell and lean
/// toward the pointer, squash when pressed and wobble back on release.
private struct RecorderStyle: ButtonStyle {
    let recording: Bool
    func makeBody(configuration: Configuration) -> some View {
        RecorderBody(label: configuration.label, pressed: configuration.isPressed, recording: recording)
    }
}

private struct RecorderBody<Label: View>: View {
    let label: Label
    let pressed: Bool
    let recording: Bool
    @State private var point: CGPoint?
    @State private var size = CGSize.zero
    @Environment(\.appearance) private var look

    var body: some View {
        let lean = point.map { CGSize(width: ($0.x / max(size.width, 1) - 0.5) * 6, height: ($0.y / max(size.height, 1) - 0.5) * 4) } ?? .zero
        label
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(recording ? 0.1 : 0)))
            .offset(look.hoverMotion ? lean : .zero)
            .scaleEffect(x: pressed ? 1.06 : (point != nil && look.hoverMotion ? 1.05 : 1), y: pressed ? 0.9 : (point != nil && look.hoverMotion ? 1.05 : 1))
            .animation(pressed ? Theme.press : Theme.release, value: pressed)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.7)) { point = p }
                case .ended: withAnimation(Theme.release) { point = nil }
                }
            }
            .onChange(of: pressed) { _, d in if d { Sounds.play(.click) } }
    }
}

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
                    Keycaps(display: display, size: 14, room: 1.5)
                }
            }
            .font(.app(12, .medium))
            .padding(.horizontal, 6)
            .frame(minWidth: 128, minHeight: 34, alignment: .trailing)
            .fixedSize()
            .overlay { if recording { RecordingRing().transition(.opacity) } }
            .animation(Theme.snappy, value: recording)
            .animation(Theme.bouncy, value: display)
            .contentShape(Rectangle())
        }
        .buttonStyle(RecorderStyle(recording: recording))
        .help(recording ? "Press a combo · esc cancel" : "Click to record a new shortcut")
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
