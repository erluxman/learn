import SwiftUI

/// The Cleaner's own window (opened from Settings ▸ Cleaner): Learn's borderless glass window, so the surface can
/// have its own corners and the round button can hang off its bottom edge.
final class CleanerWindow {
    static let shared = CleanerWindow()
    private var window: GlassWindow?
    private let state = CleanerState()

    func show() {
        if window == nil {
            let s = CleanerLayout.size
            let w = GlassWindow(size: NSSize(width: s.width, height: s.height), minSize: NSSize(width: 860, height: 540), margin: CleanerLayout.margin)
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

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CleanerLayout.radius, style: .continuous)
        CleanerSurface(state: state)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.75))
            .overlay(alignment: .top) { WindowDragArea().frame(height: 40).padding(.leading, state.module == .smartCare && state.phase == .results ? 200 : 84) }
            .overlay(alignment: .topLeading) { TrafficLights(window: window).padding(.top, 14).padding(.leading, 16) }
            .background { Button("") { window.close() }.keyboardShortcut("w").opacity(0) }
            .shadow(color: .black.opacity(0.5), radius: 40, y: 22)
            .overlay(alignment: .bottom) {
                CleanerActionButton(state: state)
                    .offset(x: sidebarShift, y: (CleanerLayout.button + 20) / 2 - CleanerLayout.buttonLift)
            }
            .modifier(Jelly(motion: window.motion))
            .padding(window.margin)
    }

    /// The button centres under the page, not the whole window.
    private var sidebarShift: CGFloat {
        (state.module == .smartCare && state.phase != .home ? CleanerLayout.rail : CleanerLayout.sidebar) / 2
    }
}
