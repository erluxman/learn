import SwiftUI

/// The Cleaner's own window (a secret: double-click the General page's big icon in Settings): Learn's borderless glass window, so the surface can
/// have its own corners and the round button can hang off its bottom edge.
final class CleanerWindow {
    static let shared = CleanerWindow()
    private var window: GlassWindow?
    private let state = CleanerState()

    func show() {
        if window == nil {
            let s = CleanerLayout.size
            let w = GlassWindow(size: NSSize(width: s.width, height: s.height), minSize: NSSize(width: 860, height: 560), margin: CleanerLayout.margin)
            w.title = "Cleaner"
            let host = NSHostingView(rootView: AppearanceRoot { CleanerRoot(state: state, window: w) })
            host.sizingOptions = []
            w.host(host)
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Surface in one rounded shape, window buttons on it, and the round button straddling its bottom edge.
private struct CleanerRoot: View {
    @ObservedObject var state: CleanerState
    let window: GlassWindow
    @Environment(\.appearance) private var look

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: look.radius, style: .continuous)
        CleanerSurface(state: state)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(shape)
            .modifier(CleanerFinish(shape: shape, glass: look.surface == .glass))
            // As Learn Settings: glass follows the system look, the gradient is always dark.
            .onAppear { window.appearance = look.surface == .glass ? nil : NSAppearance(named: .darkAqua) }
            .onChange(of: look.surface) { _, s in window.appearance = s == .glass ? nil : NSAppearance(named: .darkAqua) }
            .overlay(alignment: .top) { WindowDragArea().frame(height: 40).padding(.leading, state.module == .smartCare && state.phase == .results ? 200 : 84) }
            .overlay(alignment: .topLeading) { TrafficLights(window: window).padding(.top, look.cornerInset(14)).padding(.leading, look.cornerInset(16)) }
            .overlay(alignment: .topTrailing) { DebugBadge() }
            .background { Button("") { window.close() }.keyboardShortcut("w").opacity(0) }
            .shadow(color: .black.opacity(0.5), radius: 40, y: 22)
            .overlay(alignment: .bottom) {
                CleanerActionButton(state: state)
                    .offset(x: sidebarShift, y: (CleanerLayout.button + 20) / 2 - CleanerLayout.buttonLift)
            }
            .modifier(Jelly(motion: window.motion))
            .padding(window.margin)
    }

    /// Same surface as Settings (Settings ▸ Appearance), built the same way: glass with its rim, or over the gradient a
    /// fine light edge.
    private struct CleanerFinish<S: InsettableShape>: ViewModifier {
        let shape: S
        let glass: Bool
        func body(content: Content) -> some View {
            if glass { content.liquidGlass(in: shape).glassRim(shape) }
            else { content.overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.75)) }
        }
    }

    /// The button centres under the page, not the whole window.
    private var sidebarShift: CGFloat {
        state.module == .smartCare && state.phase != .home ? CleanerLayout.rail / 2
            : (CleanerLayout.sidebar - CleanerLayout.pageTrailing) / 2   // under the page's centred content
    }
}
