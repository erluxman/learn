import SwiftUI

/// Borderless window whose only visible shape is the SwiftUI glass inside it (one corner, no system rim).
/// Leaves `JellyMotion.margin` of clear space around the glass so it can wobble when the window is dragged.
/// Moves only from its title strip (`WindowDragArea`), so drags on controls stay with the controls;
/// resizes from grips on the glass's edges and corners.
final class GlassWindow: NSWindow {
    let motion = JellyMotion()

    init(size: NSSize, minSize glassMin: NSSize) {
        let m = JellyMotion.margin
        super.init(contentRect: NSRect(x: 0, y: 0, width: size.width + 2 * m, height: size.height + 2 * m),
                   styleMask: [.borderless, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false   // SwiftUI draws the shadow so it follows the glass as it wobbles
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false   // closed windows are shown again later
        minSize = NSSize(width: glassMin.width + 2 * m, height: glassMin.height + 2 * m)
        motion.attach(self)
    }

    /// Hosts `view` with resize grips laid over the glass's edges.
    func host(_ view: NSView) {
        let root = GripContainer()
        root.addSubview(view)
        view.autoresizingMask = [.width, .height]
        view.frame = root.bounds
        for edges: ResizeGrip.Edges in [.left, .right, .top, .bottom, [.top, .left], [.top, .right], [.bottom, .left], [.bottom, .right]] {
            root.addSubview(ResizeGrip(edges))
        }
        contentView = root
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performClose(_ sender: Any?) { close() }
    override func performMiniaturize(_ sender: Any?) { miniaturize(sender) }
}

/// Window drags turn into a lag the glass trails by, then springs back from with a wobble — like jelly.
final class JellyMotion: ObservableObject {
    static let margin: CGFloat = 36
    static let maxLag: CGFloat = 6

    @Published var lag = CGSize.zero
    var paused = false   // resizing moves the origin too; that isn't a drag
    private var last: NSPoint?
    private var observer: Any?

    func attach(_ w: NSWindow) {
        last = w.frame.origin
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: w, queue: .main) { [weak self, weak w] _ in
            guard let self, let w else { return }
            let o = w.frame.origin
            defer { self.last = o }
            let wobble = Prefs.shared.appearance.wobble
            guard let l = self.last, wobble > 0, !self.paused, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            let d = CGSize(width: o.x - l.x, height: -(o.y - l.y))   // SwiftUI's y points down
            guard abs(d.width) < 160, abs(d.height) < 160 else { return }   // jumps (re-centering, new screen) aren't drags
            let m = Self.maxLag * min(wobble, 1.5), k = 0.22 * wobble
            let next = CGSize(width: min(max(self.lag.width - d.width * k, -m), m),
                              height: min(max(self.lag.height - d.height * k, -m), m))
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { self.lag = next }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.55)) { self.lag = .zero }
            }
        }
    }

    deinit { observer.map(NotificationCenter.default.removeObserver) }
}

/// Trails the window by `lag` and stretches along the motion, squashing across it.
struct Jelly: ViewModifier {
    @ObservedObject var motion: JellyMotion
    func body(content: Content) -> some View {
        let l = motion.lag, k: CGFloat = 1 / 420
        content
            .scaleEffect(x: 1 + abs(l.width) * k - abs(l.height) * k / 2,
                         y: 1 + abs(l.height) * k - abs(l.width) * k / 2)
            .offset(l)
    }
}

/// Close / minimize / (disabled) zoom, drawn like the system's; glyphs appear when the group is hovered.
struct TrafficLights: View {
    weak var window: NSWindow?
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            light(.red, "xmark") { window?.close() }
            light(.yellow, "minus") { window?.miniaturize(nil) }
            light(Color.gray.opacity(0.45), nil) {}
        }
        .onHover { hover = $0 }
    }

    private func light(_ color: Color, _ glyph: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(color)
                .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
                .frame(width: 12, height: 12)
                .overlay {
                    if let glyph, hover {
                        Image(systemName: glyph).font(.system(size: 7, weight: .black)).foregroundStyle(.black.opacity(0.55))
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(glyph == nil)
    }
}

// MARK: Moving and resizing

/// Title strip: dragging here moves the window (with the jelly); everywhere else belongs to the controls.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
        }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ v: NSView, context: Context) {}
}

/// Lays the grips out along the glass, which sits `JellyMotion.margin` inside the window.
private final class GripContainer: NSView {
    override func layout() {
        super.layout()
        let glass = bounds.insetBy(dx: JellyMotion.margin, dy: JellyMotion.margin)
        let t: CGFloat = 10, c: CGFloat = 18   // edge thickness (half in, half out), corner size
        for case let g as ResizeGrip in subviews {
            let e = g.edges
            var r = NSRect.zero
            if e == .left { r = NSRect(x: glass.minX - t / 2, y: glass.minY + c, width: t, height: glass.height - 2 * c) }
            if e == .right { r = NSRect(x: glass.maxX - t / 2, y: glass.minY + c, width: t, height: glass.height - 2 * c) }
            if e == .top { r = NSRect(x: glass.minX + c, y: glass.maxY - t / 2, width: glass.width - 2 * c, height: t) }
            if e == .bottom { r = NSRect(x: glass.minX + c, y: glass.minY - t / 2, width: glass.width - 2 * c, height: t) }
            if e.count == 2 {
                let x = e.contains(.left) ? glass.minX - c / 2 : glass.maxX - c / 2
                let y = e.contains(.bottom) ? glass.minY - c / 2 : glass.maxY - c / 2
                r = NSRect(x: x, y: y, width: c, height: c)
            }
            g.frame = r
        }
    }
}

final class ResizeGrip: NSView {
    struct Edges: OptionSet, Hashable {
        let rawValue: Int
        static let left = Edges(rawValue: 1), right = Edges(rawValue: 2), top = Edges(rawValue: 4), bottom = Edges(rawValue: 8)
        var count: Int { rawValue.nonzeroBitCount }
    }
    let edges: Edges
    private var start: (frame: NSRect, mouse: NSPoint)?

    init(_ edges: Edges) { self.edges = edges; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }

    private var cursor: NSCursor {
        if #available(macOS 15, *) {
            let p: NSCursor.FrameResizePosition = switch edges {
            case .left: .left
            case .right: .right
            case .top: .top
            case .bottom: .bottom
            case [.top, .left]: .topLeft
            case [.top, .right]: .topRight
            case [.bottom, .left]: .bottomLeft
            default: .bottomRight
            }
            return .frameResize(position: p, directions: .all)
        }
        return edges.contains(.left) || edges.contains(.right) ? .resizeLeftRight : .resizeUpDown
    }

    override func mouseDown(with event: NSEvent) {
        guard let w = window else { return }
        start = (w.frame, NSEvent.mouseLocation)
        (w as? GlassWindow)?.motion.paused = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let w = window, let s = start else { return }
        let m = NSEvent.mouseLocation, dx = m.x - s.mouse.x, dy = m.y - s.mouse.y
        var f = s.frame
        if edges.contains(.right) { f.size.width = max(s.frame.width + dx, w.minSize.width) }
        if edges.contains(.left) {
            f.size.width = max(s.frame.width - dx, w.minSize.width)
            f.origin.x = s.frame.maxX - f.width
        }
        if edges.contains(.top) { f.size.height = max(s.frame.height + dy, w.minSize.height) }
        if edges.contains(.bottom) {
            f.size.height = max(s.frame.height - dy, w.minSize.height)
            f.origin.y = s.frame.maxY - f.height
        }
        w.setFrame(f, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        start = nil
        (window as? GlassWindow)?.motion.paused = false
    }
}
