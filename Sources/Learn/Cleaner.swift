import SwiftUI

/// Mac cleaner laid out like CleanMyMac: one gradient surface per module (the sidebar sits on it, not beside it),
/// a 3D glass hero, a round Scan button hanging off the window's bottom edge, and Smart Care's card grid where the
/// area being scanned grows while the others wait. Scans only read (sizes, counts, names); nothing is removed yet.

// MARK: Model

enum CleanerModule: String, CaseIterable, Identifiable {
    case smartCare, cleanup, protection, performance, applications, clutter

    var id: Self { self }
    var title: String {
        switch self {
        case .smartCare: "Smart Care"
        case .cleanup: "Cleanup"
        case .protection: "Protection"
        case .performance: "Performance"
        case .applications: "Applications"
        case .clutter: "My Clutter"
        }
    }
    var heading: String { self == .smartCare ? "Welcome back!" : title }
    var subtitle: String {
        switch self {
        case .smartCare: "Start with a quick and extensive scan of your Mac."
        case .cleanup: "Clean your system to achieve maximum performance\nand reclaim free space."
        case .protection: "Check your Mac for all kinds of threats and vulnerabilities."
        case .performance: "Run recommended maintenance tasks to optimize\nyour Mac's performance."
        case .applications: "Take control of your applications. Uninstall, update\nor remove old application leftovers."
        case .clutter: "Sort through your storage to delete your unneeded files and\nbring the mess down to the minimum."
        }
    }
    /// Scanning headline for this area (Smart Care's cards and the module's own scan).
    var scanning: String {
        switch self {
        case .smartCare: "Scanning your Mac..."
        case .cleanup: "Looking for junk..."
        case .protection: "Looking for threats..."
        case .performance: "Examining your system..."
        case .applications: "Checking your apps..."
        case .clutter: "Analyzing your storage..."
        }
    }

    /// The surface: gradient `bg` (top-left → bottom-right), a glow that sits behind the hero, a second drifting light.
    var bg: [Color] {
        switch self {
        case .smartCare: [Color(hex: 0x4A129E), Color(hex: 0x3A0C86), Color(hex: 0x1E0752)]
        case .cleanup: [Color(hex: 0x3E7F12), Color(hex: 0x1D7426), Color(hex: 0x0A3C12)]
        case .protection: [Color(hex: 0xB0137A), Color(hex: 0x9A0E6C), Color(hex: 0x520640)]
        case .performance: [Color(hex: 0xCE6418), Color(hex: 0xB24E14), Color(hex: 0x62220A)]
        case .applications: [Color(hex: 0x1B4CC0), Color(hex: 0x163FA8), Color(hex: 0x3A1C98)]
        case .clutter: [Color(hex: 0x127E72), Color(hex: 0x0E6A62), Color(hex: 0x073E3C)]
        }
    }
    var glow: Color {
        switch self {
        case .smartCare: Color(hex: 0xC02CC0)
        case .cleanup: Color(hex: 0x34B04A)
        case .protection: Color(hex: 0xEE3FA8)
        case .performance: Color(hex: 0xF49244)
        case .applications: Color(hex: 0x3A88EA)
        case .clutter: Color(hex: 0x30BDA4)
        }
    }
    var accent: Color {
        switch self {
        case .smartCare: Color(hex: 0x7A2AD8)
        case .cleanup: Color(hex: 0x6E9A10)
        case .protection: Color(hex: 0x7A1AB0)
        case .performance: Color(hex: 0xD8402A)
        case .applications: Color(hex: 0x5A2AC8)
        case .clutter: Color(hex: 0x1C8AA8)
        }
    }
    /// Round button fill.
    var button: Color {
        switch self {
        case .smartCare: Color(hex: 0xD530B4)
        case .cleanup: Color(hex: 0x3C9A34)
        case .protection: Color(hex: 0xE0369E)
        case .performance: Color(hex: 0xDB6A20)
        case .applications: Color(hex: 0x2A7FE0)
        case .clutter: Color(hex: 0x1FA08C)
        }
    }
    /// Bottom color of this area's card while it's being scanned in Smart Care.
    var cardLight: Color {
        switch self {
        case .cleanup: Color(hex: 0x4DE889)
        case .protection: Color(hex: 0xF2479F)
        case .performance: Color(hex: 0xF2A548)
        case .applications: Color(hex: 0x4AA8F0)
        case .clutter: Color(hex: 0x55E6C4)
        case .smartCare: Color(hex: 0xD530B4)
        }
    }
}

/// What a scan found. Only facts that were actually read from disk.
struct CleanerFindings {
    var junkBytes: Int64 = 0          // user caches + logs
    var agents = 0                    // launch agents / daemons outside Apple's
    var apps = 0                      // apps in /Applications
    var downloads = 0                 // items in ~/Downloads
    var tasks = ["Flush DNS Cache", "Free Up Purgeable Space"]

    var junk: String { ByteCountFormatter.string(fromByteCount: junkBytes, countStyle: .file) }
}

final class CleanerState: ObservableObject {
    enum Phase: Equatable { case home, scanning, results }

    @Published var module = CleanerModule.smartCare
    @Published var phase = Phase.home
    @Published var progress = 0.0
    @Published var stage = 0                 // Smart Care: which area is being scanned (index into `stages`)
    @Published var ticker = ""               // the file being looked at
    @Published var found = CleanerFindings()
    @Published var notice: String?

    /// Smart Care scans these in order; Applications and My Clutter share the last stage, like the original.
    static let stages: [CleanerModule] = [.cleanup, .protection, .performance, .clutter]

    private var task: Task<Void, Never>?

    func select(_ m: CleanerModule) {
        guard m != module else { return }
        stop()
        module = m
    }

    func stop() {
        task?.cancel(); task = nil
        phase = .home; progress = 0; stage = 0; ticker = ""
    }

    func scan() {
        stop()
        found = CleanerFindings()
        phase = .scanning
        let areas = module == .smartCare ? Self.stages : [module]
        task = Task { @MainActor [weak self] in
            for (i, area) in areas.enumerated() {
                guard let self, !Task.isCancelled else { return }
                self.stage = i
                await self.run(area, span: (Double(i) / Double(areas.count), Double(i + 1) / Double(areas.count)))
            }
            guard let self, !Task.isCancelled else { return }
            self.ticker = ""
            self.phase = .results
            Sounds.play(.shortcut)
        }
    }

    /// Reads what `area` looks at, feeding the ticker, for at least ~2.6 s so each stage can be seen.
    @MainActor private func run(_ area: CleanerModule, span: (Double, Double)) async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots: [URL]
        switch area {
        case .cleanup: roots = [home.appendingPathComponent("Library/Caches"), home.appendingPathComponent("Library/Logs")]
        case .protection: roots = [home.appendingPathComponent("Library/LaunchAgents"), URL(fileURLWithPath: "/Library/LaunchAgents"),
                                   URL(fileURLWithPath: "/Library/LaunchDaemons")]
        case .clutter, .smartCare: roots = [home.appendingPathComponent("Downloads")]
        case .applications: roots = [URL(fileURLWithPath: "/Applications")]
        case .performance: roots = []
        }
        let names = AsyncStream<(String, Int64)> { cont in
            let work = Task.detached(priority: .utility) {
                for root in roots {
                    let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
                    guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                                 options: area == .cleanup ? [] : [.skipsSubdirectoryDescendants]) else { continue }
                    while let url = e.nextObject() as? URL {
                        if Task.isCancelled { break }
                        let v = try? url.resourceValues(forKeys: Set(keys))
                        cont.yield((url.lastPathComponent, Int64(v?.totalFileAllocatedSize ?? 0)))
                    }
                }
                cont.finish()
            }
            cont.onTermination = { _ in work.cancel() }
        }
        let start = Date()
        var count = 0, bytes: Int64 = 0, lastTick = Date.distantPast
        for await (name, size) in names {
            if Task.isCancelled { return }
            count += 1; bytes += size
            if Date().timeIntervalSince(lastTick) > 0.07 {
                lastTick = Date()
                ticker = name
                progress = span.0 + (span.1 - span.0) * min(0.9, Date().timeIntervalSince(start) / 2.6)
            }
        }
        switch area {
        case .cleanup: found.junkBytes = bytes
        case .protection: found.agents = count
        case .clutter: found.downloads = count; found.apps = Self.appCount()
        case .applications: found.apps = count
        default: ticker = "Preparing tasks for performance optimization."
        }
        // Hold the stage on screen for a moment, finishing its share of the progress.
        while Date().timeIntervalSince(start) < 2.6 {
            try? await Task.sleep(for: .milliseconds(40))
            if Task.isCancelled { return }
            progress = span.0 + (span.1 - span.0) * min(1, Date().timeIntervalSince(start) / 2.6)
        }
        progress = span.1
    }

    private static func appCount() -> Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []).filter { $0.hasSuffix(".app") }.count
    }
}

// MARK: Motion

enum CleanerMotion {
    static let spring = Animation.spring(response: 0.5, dampingFraction: 0.86)
    static let quick = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let swap = Animation.easeInOut(duration: 0.42)
}

/// Content leaving blurs out while the new content sharpens in, as the original does between modules.
private struct BlurFade: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content.blur(radius: active ? 22 : 0).opacity(active ? 0 : 1).scaleEffect(active ? 0.97 : 1)
    }
}
extension AnyTransition {
    static var blurFade: AnyTransition { .modifier(active: BlurFade(active: true), identity: BlurFade(active: false)) }
}

// MARK: Surface

enum CleanerLayout {
    static let size = CGSize(width: 960, height: 580)
    static let margin: CGFloat = 96         // clear room: shadow, and the button's lower half and halo
    static let sidebar: CGFloat = 215
    static let rail: CGFloat = 78
    static let firstRow: CGFloat = 114      // centre of the first sidebar row, from the top
    static let rowStep: CGFloat = 64
    static let button: CGFloat = 80
    static let buttonLift: CGFloat = 13     // button centre above the surface's bottom edge
    static let radius: CGFloat = 16
}

/// The window's surface: backdrop, sidebar (or rail) and the module's page. The round button is laid over the
/// surface's bottom edge by the window root, since half of it hangs outside.
struct CleanerSurface: View {
    @ObservedObject var state: CleanerState

    private var compact: Bool { state.module == .smartCare && state.phase != .home }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                CleanerBackdrop(module: state.module)
                    .id(state.module)
                    .transition(.opacity)
            }
            .animation(CleanerMotion.swap, value: state.module)
            .allowsHitTesting(false)

            HStack(spacing: 0) {
                CleanerSidebar(state: state, compact: compact)
                    .frame(width: compact ? CleanerLayout.rail : CleanerLayout.sidebar)
                ZStack {
                    page
                        .id("\(state.module.rawValue)-\(pageKey)")
                        .transition(.blurFade)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(CleanerMotion.swap, value: state.module)
                .animation(CleanerMotion.spring, value: pageKey)
            }
            .animation(CleanerMotion.spring, value: compact)

            if compact { topBar.transition(.opacity) }
        }
        .foregroundStyle(.white)
        .background(WindowDragArea())   // any empty spot moves the window, as in the original
        .overlay(alignment: .bottom) {
            if let n = state.notice {
                Text(n).font(.system(size: 12.5, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.35)))
                    .padding(.bottom, 64)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(CleanerMotion.quick, value: state.notice)
    }

    /// Home and the module scan share a page; Smart Care's grid and every results page are their own.
    private var pageKey: String {
        switch state.phase {
        case .home: "home"
        case .scanning: state.module == .smartCare ? "grid" : "home"
        case .results: "results"
        }
    }

    @ViewBuilder private var page: some View {
        switch (state.module, state.phase) {
        case (.smartCare, .scanning), (.smartCare, .results): SmartCareGrid(state: state)
        case (_, .results): ModuleResults(state: state)
        default: ModuleHome(state: state)
        }
    }

    /// Smart Care's title strip once it's running: "‹ Start Over" beside the window buttons, the module name centred.
    private var topBar: some View {
        ZStack {
            Text("Smart Care").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            HStack {
                if state.phase == .results {
                    Button { state.stop() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                            Text("Start Over").font(.system(size: 13, weight: .medium))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 90)
                }
                Spacer()
            }
        }
        .frame(height: 28)
        .padding(.top, 2)
    }
}

// MARK: Backdrop

/// The module's gradient with slow-drifting lights; the whole window shares it.
struct CleanerBackdrop: View {
    let module: CleanerModule
    var body: some View { SurfaceBackdrop(bg: module.bg, glow: module.glow, accent: module.accent) }
}

/// A living gradient surface: `bg` top-left → bottom-right, a glow near the upper middle, an accent light drifting
/// along the bottom, and darker corners. Used by the Cleaner and by Learn Settings.
struct SurfaceBackdrop: View {
    let bg: [Color]
    let glow: Color
    let accent: Color

    /// A surface derived from one color (Settings pages), deep enough for white text.
    init(color c: Color) {
        let (h, sat, br) = c.hsb
        let tone = { (dh: Double, db: Double) in Color(hue: (h + dh + 1).truncatingRemainder(dividingBy: 1), saturation: min(1, sat * 0.9 + 0.1), brightness: max(0.08, min(1, br * db))) }
        self.init(bg: [tone(-0.02, 0.62), tone(0, 0.5), tone(0.03, 0.26)], glow: tone(0, 0.95), accent: tone(0.06, 0.6))
    }
    /// A surface from 1–3 theme colors.
    init(colors cs: [Color]) {
        let a = cs.first ?? .purple, b = cs.count > 1 ? cs[1] : a, c = cs.count > 2 ? cs[2] : b
        self.init(bg: [a.mix(.black, 0.35), b.mix(.black, 0.5), c.mix(.black, 0.75)], glow: a.mix(.black, 0.05), accent: c.mix(.black, 0.3))
    }
    init(bg: [Color], glow: Color, accent: Color) { self.bg = bg; self.glow = glow; self.accent = accent }

    var body: some View {
        LivingGradient(bg: bg.map { NSColor($0) }, glow: NSColor(glow), accent: NSColor(accent))
    }
}

/// `SurfaceBackdrop` drawn by Core Animation: the lights drift on the render server, so the surface moves without
/// SwiftUI redrawing anything (scrolling and everything else on top stay smooth).
private struct LivingGradient: NSViewRepresentable {
    let bg: [NSColor]
    let glow: NSColor
    let accent: NSColor
    func makeNSView(context: Context) -> LivingGradientView { LivingGradientView() }
    func updateNSView(_ v: LivingGradientView, context: Context) { v.set(bg: bg, glow: glow, accent: accent) }
}

final class LivingGradientView: NSView {
    private let base = CAGradientLayer()
    private let lights = (0..<3).map { _ in CAGradientLayer() }
    private let vignette = CAGradientLayer()
    private var laidOut = CGSize.zero
    /// Where each light drifts: centre (unit, y down), drift (unit), radius (× width), period (s), opacity.
    private static let paths: [(c: CGPoint, d: CGVector, r: CGFloat, t: Double, o: Float)] = [
        (CGPoint(x: 0.6, y: 0.34), CGVector(dx: 0.03, dy: 0.03), 0.42, 13, 0.75),
        (CGPoint(x: 0.95, y: 0.85), CGVector(dx: 0.08, dy: 0.1), 0.5, 19, 0.6),
        (CGPoint(x: 0.12, y: 0.95), CGVector(dx: 0.06, dy: 0.05), 0.4, 17, 0.45),
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        base.startPoint = CGPoint(x: 0, y: 1); base.endPoint = CGPoint(x: 1, y: 0)   // top-left → bottom-right
        layer?.addSublayer(base)
        for l in lights { l.type = .radial; l.startPoint = CGPoint(x: 0.5, y: 0.5); l.endPoint = CGPoint(x: 1, y: 1); layer?.addSublayer(l) }
        vignette.type = .radial
        vignette.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.28).cgColor]
        vignette.locations = [0, 0.3, 1]
        layer?.addSublayer(vignette)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func set(bg: [NSColor], glow: NSColor, accent: NSColor) {
        CATransaction.begin(); CATransaction.setAnimationDuration(0.45)
        base.colors = bg.map(\.cgColor)
        for (i, l) in lights.enumerated() {
            let c = i == 0 ? glow : accent
            l.colors = [c.withAlphaComponent(CGFloat(Self.paths[i].o)).cgColor, c.withAlphaComponent(0).cgColor]
        }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        guard bounds.size != laidOut else { return }
        laidOut = bounds.size
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let w = bounds.width, h = bounds.height
        base.frame = bounds
        vignette.frame = bounds.insetBy(dx: -w * 0.25, dy: -h * 0.25)
        vignette.startPoint = CGPoint(x: 0.56, y: 0.58); vignette.endPoint = CGPoint(x: 1.1, y: 1.1)
        for (i, l) in lights.enumerated() {
            let p = Self.paths[i], r = w * p.r
            l.bounds = CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r)
            let at = { (u: CGPoint) in CGPoint(x: u.x * w, y: (1 - u.y) * h) }   // layer y is up
            l.position = at(p.c)
            let drift = CABasicAnimation(keyPath: "position")
            drift.fromValue = at(CGPoint(x: p.c.x - p.d.dx, y: p.c.y - p.d.dy))
            drift.toValue = at(CGPoint(x: p.c.x + p.d.dx, y: p.c.y + p.d.dy))
            drift.duration = p.t
            drift.autoreverses = true
            drift.repeatCount = .infinity
            drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            l.add(drift, forKey: "drift")
        }
        CATransaction.commit()
    }
}

extension Color {
    var hsb: (Double, Double, Double) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        (NSColor(self).usingColorSpace(.sRGB) ?? .gray).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h, s, b)
    }
}

// MARK: Sidebar

private struct CleanerSidebar: View {
    @ObservedObject var state: CleanerState
    let compact: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            // One pill that slides to the selected row, like Learn Settings.
            if let i = CleanerModule.allCases.firstIndex(of: state.module) {
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                shape.fill(.white.opacity(0.12))
                    .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.08)],
                                                               startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                    .frame(width: compact ? 54 : 188, height: 54)
                    .position(x: compact ? CleanerLayout.rail / 2 + 6 : CleanerLayout.sidebar / 2,
                              y: CleanerLayout.firstRow + CGFloat(i) * CleanerLayout.rowStep)
                    .animation(.spring(response: 0.45, dampingFraction: 0.78), value: i)
            }
            ForEach(Array(CleanerModule.allCases.enumerated()), id: \.element) { i, m in
                SidebarItem(module: m, selected: state.module == m, compact: compact,
                            progress: m == .smartCare && compact ? (state.phase == .results ? 1 : state.progress) : nil) {
                    Sounds.play(.click)
                    withAnimation(CleanerMotion.swap) { state.select(m) }
                }
                .position(x: compact ? CleanerLayout.rail / 2 + 6 : CleanerLayout.sidebar / 2,
                          y: CleanerLayout.firstRow + CGFloat(i) * CleanerLayout.rowStep)
            }
            GeometryReader { g in
                AssistantItem(compact: compact)
                    .position(x: compact ? CleanerLayout.rail / 2 + 6 : CleanerLayout.sidebar / 2, y: g.size.height - 44)
            }
        }
        .frame(maxHeight: .infinity)
        // The only separation from the page: a hairline that fades out at both ends.
        .overlay(alignment: .trailing) {
            if !compact {
                LinearGradient(colors: [.white.opacity(0), .white.opacity(0.13), .white.opacity(0.13), .white.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: 1)
                    .padding(.top, 140).padding(.bottom, 170)
            }
        }
    }
}

private struct SidebarItem: View {
    let module: CleanerModule
    let selected: Bool
    let compact: Bool
    let progress: Double?
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button(action: action) {
            HStack(spacing: 14) {
                ModuleIcon(module: module, size: 34, mono: !selected && module != .smartCare, animating: (progress ?? 1) < 1)
                    .frame(width: 30, height: 30)
                    .modifier(IconHover(size: 30))
                if !compact {
                    Text(module.title).font(.system(size: 14.5, weight: .medium)).fixedSize()
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, compact ? 10 : 18)
            .frame(width: compact ? 54 : 188, height: 54)
            .background { if hover && !selected { shape.fill(.white.opacity(0.06)) } }
            .overlay(alignment: .topTrailing) {
                if let progress { ProgressPie(value: progress).frame(width: 13, height: 13).offset(x: 4, y: -4) }
            }
            .contentShape(shape)
        }
        .buttonStyle(CleanerPressStyle())
        .onHover { h in withAnimation(CleanerMotion.quick) { hover = h } }
    }
}

private struct ProgressPie: View {
    let value: Double
    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.35))
            PieSlice(fraction: value).fill(.white)
        }
        .overlay(Circle().strokeBorder(.white, lineWidth: 1))
        .animation(.linear(duration: 0.1), value: value)
    }
}

private struct PieSlice: Shape {
    var fraction: Double
    var animatableData: Double { get { fraction } set { fraction = newValue } }
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        p.move(to: c)
        p.addArc(center: c, radius: r.width / 2, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
        p.closeSubpath()
        return p
    }
}

private struct AssistantItem: View {
    let compact: Bool
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.75))
                HStack(spacing: 3) {
                    Circle().fill(.white.opacity(0.9)).frame(width: 9, height: 9)
                    Circle().fill(.white.opacity(0.6)).frame(width: 5, height: 5)
                }
            }
            .frame(width: 28, height: 28)
            if !compact {
                Text("Assistant").font(.system(size: 14.5, weight: .medium))
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, compact ? 13 : 18)
        .frame(width: compact ? 54 : 188, height: 44)
    }
}

// MARK: Module home

private struct ModuleHome: View {
    @ObservedObject var state: CleanerState

    var body: some View {
        let m = state.module, scanning = state.phase == .scanning
        GeometryReader { g in
            let h = g.size.height
            VStack(spacing: 0) {
                ZStack {
                    ModuleIcon(module: m, size: 300, animating: scanning)
                        .modifier(IconHover(size: 300))
                        .scaleEffect(scanning ? 0.9 : 1)
                    if scanning {
                        Circle().trim(from: 0, to: state.progress)
                            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 300, height: 300)
                            .shadow(color: .white.opacity(0.5), radius: 6)
                            .transition(.opacity)
                    }
                }
                .frame(height: 300)
                .position(x: g.size.width / 2, y: h * 0.36)
                .frame(height: 0)
                Spacer(minLength: 0)
            }
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text(scanning ? m.scanning : m.heading).font(.system(size: 36, weight: .regular))
                        .contentTransition(.opacity)
                    if m == .clutter && !scanning { NewBadge() }
                }
                .allowsHitTesting(false)
                Text(scanning ? state.ticker : m.subtitle)
                    .font(.system(size: 15)).foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center).lineSpacing(4)
                    .lineLimit(scanning ? 1 : 3).truncationMode(.middle)
                    .frame(maxWidth: 520)
                    .allowsHitTesting(false)
                if !scanning {
                    if m == .protection { SmallPill(title: "Configure Scan").padding(.top, 8) }
                    if m == .clutter { FolderPicker().padding(.top, 10) }
                }
            }
            .frame(width: g.size.width)
            .position(x: g.size.width / 2, y: h * 0.7 + (m == .clutter || m == .protection ? 14 : 0))
        }
        .animation(CleanerMotion.spring, value: scanning)
    }
}

private struct NewBadge: View {
    var body: some View {
        Text("New").font(.system(size: 10, weight: .bold)).foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color(hex: 0xF6DC2A)))
            .offset(y: 2)
    }
}

private struct SmallPill: View {
    let title: String
    var body: some View {
        Button {} label: {
            Text(title).font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.18)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.2)))
        }
        .buttonStyle(CleanerPressStyle())
    }
}

/// Which folder My Clutter looks in: home, or one of its top-level folders.
private struct FolderPicker: View {
    @State private var folder = NSUserName()
    private let folders: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []
        return names.filter { !$0.hasPrefix(".") && $0 != "Library" }.sorted()
    }()
    var body: some View {
        Menu {
            Button(NSUserName()) { folder = NSUserName() }
            Divider()
            ForEach(folders, id: \.self) { f in Button(f) { folder = f } }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: folder == NSUserName() ? "house.fill" : "folder.fill").font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x7FD0FF))
                Text(folder).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 10).frame(width: 170, height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.2)))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: Smart Care grid

/// Scanning: three cards on top (Cleanup, Protection, Performance), two below (Applications, My Clutter); the area
/// being scanned widens and lights up in its color. Results: all cards even, each with what was found.
private struct SmartCareGrid: View {
    @ObservedObject var state: CleanerState

    var body: some View {
        let results = state.phase == .results
        let active: CleanerModule? = results ? nil : CleanerState.stages[min(state.stage, CleanerState.stages.count - 1)]
        GeometryReader { g in
            let gap: CGFloat = 10, top: CGFloat = results ? 92 : 42, bottomPad: CGFloat = 64
            let W = g.size.width - 20, H = g.size.height - top - bottomPad
            let bottomActive = active == .clutter
            let topH = results ? (H - gap) * 0.5 : (bottomActive ? (H - gap) * 0.36 : (H - gap) * 0.62)
            let bottomH = H - gap - topH
            VStack(alignment: .leading, spacing: gap) {
                row([.cleanup, .protection, .performance], active: active, width: W, height: topH, gap: gap)
                row([.applications, .clutter], active: active, width: W, height: bottomH, gap: gap)
            }
            .padding(.top, top)
            .overlay(alignment: .top) {
                if results {
                    Text("Your tasks are ready to run. Look what we found:")
                        .font(.system(size: 22, weight: .medium))
                        .padding(.top, 44)
                        .transition(.opacity)
                }
            }
        }
        .padding(.trailing, 20)
        .animation(CleanerMotion.spring, value: state.stage)
        .animation(CleanerMotion.spring, value: results)
    }

    private func row(_ areas: [CleanerModule], active: CleanerModule?, width: CGFloat, height: CGFloat, gap: CGFloat) -> some View {
        let wide: CGFloat = areas.count == 3 ? 2.3 : 3.2
        let weights = areas.map { active == nil ? 1 : ($0 == active ? wide : 1) }
        let unit = (width - gap * CGFloat(areas.count - 1)) / weights.reduce(0, +)
        return HStack(spacing: gap) {
            ForEach(Array(areas.enumerated()), id: \.element) { i, a in
                AreaCard(area: a, state: state, active: a == active, scanned: isScanned(a))
                    .frame(width: unit * weights[i], height: height)
            }
        }
    }

    private func isScanned(_ a: CleanerModule) -> Bool {
        if state.phase == .results { return true }
        let order: [CleanerModule: Int] = [.cleanup: 0, .protection: 1, .performance: 2, .applications: 3, .clutter: 3]
        return (order[a] ?? 9) < state.stage
    }
}

private struct AreaCard: View {
    let area: CleanerModule
    @ObservedObject var state: CleanerState
    let active: Bool
    let scanned: Bool
    @State private var checked = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let results = state.phase == .results
        GeometryReader { g in
            let s = g.size
            ZStack(alignment: .topLeading) {
                // Card glass: dark and quiet, or lit in the area's color while it's being scanned.
                shape.fill(.white.opacity(0.07))
                if active {
                    shape.fill(LinearGradient(colors: [.white.opacity(0.1), area.cardLight.opacity(0.95)], startPoint: .top, endPoint: .bottom))
                        .transition(.opacity)
                }
                shape.strokeBorder(.white.opacity(active ? 0.25 : 0.1), lineWidth: 1)

                if active {
                    VStack(spacing: 0) {
                        Text(area.scanning).font(.system(size: 26, weight: .semibold)).padding(.top, 20)
                        Spacer(minLength: 0)
                        ModuleIcon(module: area, size: min(s.height * 0.56, s.width * 0.5), animating: true)
                        Spacer(minLength: 0)
                        Text(state.ticker).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1).truncationMode(.middle).frame(maxWidth: s.width * 0.8)
                            .padding(.bottom, 14)
                    }
                    .frame(width: s.width, height: s.height)
                    .transition(.opacity)
                } else {
                    // Icon peeking in from the bottom while the area waits; once it's scanned it moves up to the top
                    // corner, leaving the bottom for what was found.
                    let corner = results || scanned
                    ModuleIcon(module: area, size: min(s.height, 200) * (corner ? 0.7 : 0.9))
                        .position(x: corner ? s.width - min(s.height, 200) * 0.2 : s.width * 0.62,
                                  y: corner ? min(s.height, 200) * 0.18 : s.height * 0.95)
                        .opacity(0.95)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            if results {
                                Button { checked.toggle(); Sounds.play(.click) } label: { CheckBox(on: checked) }.buttonStyle(.plain)
                            }
                            Text(area.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                        }
                        Spacer(minLength: 0)
                        if scanned, let (value, sub) = finding {
                            Text(value).font(.system(size: 21, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(sub).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.6)).padding(.top, 2)
                                .transition(.opacity)
                        }
                    }
                    .padding(16)
                    .frame(width: s.width, height: s.height, alignment: .topLeading)
                    .overlay(alignment: .bottomTrailing) {
                        if results, reviewable {
                            Button("Review") { state.notice = "Review comes with the \(area.title) module." }
                                .buttonStyle(ReviewStyle()).padding(14)
                        }
                    }
                }
            }
            .clipShape(shape)
        }
        .animation(CleanerMotion.spring, value: active)
        .animation(CleanerMotion.spring, value: scanned)
    }

    private var reviewable: Bool { area == .cleanup || area == .performance }

    /// Only what the scan really read.
    private var finding: (String, String)? {
        let f = state.found
        switch area {
        case .cleanup: return ("\(f.junk) of junk", "to clean")
        case .protection: return ("\(f.agents) startup agents", "to check")
        case .performance: return ("\(f.tasks.count) tasks", "to run")
        case .applications: return ("\(f.apps) apps", "installed")
        case .clutter: return ("\(f.downloads) downloads", "to review")
        case .smartCare: return nil
        }
    }
}

private struct CheckBox: View {
    let on: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(on ? 0.18 : 0.08))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .overlay { if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) } }
            .frame(width: 22, height: 22)
    }
}

private struct ReviewStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(configuration.isPressed ? 0.28 : 0.16)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.28)))
            .onChange(of: configuration.isPressed) { _, d in if d { Sounds.play(.click) } }
    }
}

// MARK: Module results

/// A single module's scan result (its full review screen is built with the module).
private struct ModuleResults: View {
    @ObservedObject var state: CleanerState
    var body: some View {
        let m = state.module, f = state.found
        let line: String = switch m {
        case .cleanup: "\(f.junk) of junk found in caches and logs."
        case .protection: "\(f.agents) startup agents and daemons to check."
        case .performance: "\(f.tasks.count) maintenance tasks ready: \(f.tasks.joined(separator: ", "))."
        case .applications: "\(f.apps) apps installed."
        case .clutter: "\(f.downloads) items in Downloads to review."
        case .smartCare: ""
        }
        GeometryReader { g in
            ModuleIcon(module: m, size: 220).position(x: g.size.width / 2, y: g.size.height * 0.36)
            VStack(spacing: 10) {
                Text("Scan complete").font(.system(size: 34))
                Text(line).font(.system(size: 15)).foregroundStyle(.white.opacity(0.78))
                Button("Start Over") { state.stop() }.buttonStyle(ReviewStyle()).padding(.top, 6)
            }
            .frame(width: g.size.width)
            .position(x: g.size.width / 2, y: g.size.height * 0.7)
        }
    }
}

// MARK: Round button

/// The big round action button (Scan / Stop / Run). The window root places it so it hangs over the bottom edge.
struct CleanerActionButton: View {
    @ObservedObject var state: CleanerState
    @State private var hover = false
    @State private var pressed = false

    var body: some View {
        let label: String = switch state.phase { case .home: "Scan"; case .scanning: "Stop"; case .results: state.module == .smartCare ? "Run" : "Scan" }
        let color = state.module.button
        let d = CleanerLayout.button
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let breathe = 0.5 + 0.5 * sin(ctx.date.timeIntervalSinceReferenceDate * 2.2)
            ZStack {
                // Halo spilling onto the surface.
                Circle().fill(RadialGradient(colors: [color.opacity(0.5 + 0.2 * breathe), color.opacity(0)], center: .center,
                                             startRadius: d * 0.35, endRadius: d * 0.95))
                    .frame(width: d * 1.9, height: d * 1.9)
                // Soft shadow under the disc: the only depth it needs; flattens when pressed.
                Ellipse().fill(.black.opacity(pressed ? 0.4 : 0.3))
                    .frame(width: d * 0.92, height: d * 0.3).blur(radius: pressed ? 5 : 8)
                    .offset(y: d * 0.45 + (pressed ? 1 : 5))
                Ellipse().fill(.black.opacity(0.18))
                    .frame(width: d * 1.1, height: d * 0.45).blur(radius: 14)
                    .offset(y: d * 0.45 + (pressed ? 3 : 12))
                // Face: a flat disc, lit a little from the top, with a white rim.
                ZStack {
                    Circle().fill(LinearGradient(colors: [color.mix(.white, 0.22), color, color.mix(.black, 0.1)],
                                                 startPoint: .top, endPoint: .bottom))
                    Circle().fill(RadialGradient(colors: [.white.opacity(pressed ? 0.15 : 0.28), .clear], center: UnitPoint(x: 0.5, y: 0.15),
                                                 startRadius: 0, endRadius: d * 0.6))
                    Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2)
                    if state.phase == .scanning {
                        Circle().trim(from: 0, to: state.progress)
                            .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(-7)
                            .animation(.linear(duration: 0.1), value: state.progress)
                    }
                    Text(label).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                        .contentTransition(.opacity)
                }
                .frame(width: d, height: d)
            }
            .scaleEffect(pressed ? 0.95 : hover ? 1.04 : 1)
        }
        .frame(width: d + 20, height: d + 20)
        .contentShape(Circle())
        .onHover { h in withAnimation(CleanerMotion.quick) { hover = h } }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !pressed { withAnimation(.spring(response: 0.12, dampingFraction: 0.8)) { pressed = true } } }
            .onEnded { _ in
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { pressed = false }
                Sounds.play(.click)
                act()
            })
        .animation(CleanerMotion.spring, value: state.module)
    }

    private func act() {
        withAnimation(CleanerMotion.spring) {
            switch state.phase {
            case .home: state.scan()
            case .scanning: state.stop()
            case .results:
                if state.module == .smartCare { state.notice = "Running tasks comes next — we'll build Cleanup first." }
                else { state.scan() }
            }
        }
    }
}

private struct CleanerPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(CleanerMotion.quick, value: configuration.isPressed)
    }
}
