import Combine
import SwiftUI

/// Borderless window whose only visible shape is the SwiftUI glass inside it (one corner, no system rim).
/// Leaves `JellyMotion.margin` of clear space around the glass so it can wobble when the window is dragged.
/// Moves only from its title strip (`WindowDragArea`), so drags on controls stay with the controls;
/// resizes from grips on the glass's edges and corners.
final class GlassWindow: NSWindow {
    let motion = JellyMotion()
    /// Clear space around the glass: room for the wobble, the shadow and anything that hangs off the edge.
    let margin: CGFloat

    init(size: NSSize, minSize glassMin: NSSize, margin m: CGFloat = JellyMotion.margin) {
        margin = m
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

/// Solid while you drag — the glass moves exactly with the window. When you let go it's dropped: it carries on a little
/// with the drag's momentum, dips, and springs back with a couple of soft wobbles, simulated every display frame.
/// Settings ▸ Appearance ▸ Jelly wobble loosens the spring (more give, more bounce); 0 turns it off.
final class JellyMotion: NSObject, ObservableObject {
    static let margin: CGFloat = 36
    static let maxLag: CGFloat = 7

    @Published private(set) var lag = CGSize.zero
    var paused = false { didSet { if paused { settle() } } }   // resizing moves the origin too; that isn't a drag
    static var mouseHeld: () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 }   // swappable for tests

    private weak var window: NSWindow?
    private var observer: Any?
    private var link: CADisplayLink?
    private var anchor = CGPoint.zero     // where the window is (SwiftUI orientation: y down)
    private var glass = CGPoint.zero      // where the glass is; the spring pulls it to `anchor`
    private var velocity = CGVector.zero  // the glass's, once released
    private var dragVelocity = CGVector.zero   // the window's while held, smoothed
    private var dragging = false
    private var lastStep: CFTimeInterval = 0
    private var lastMouse: CGPoint?

    func attach(_ w: NSWindow) {
        window = w
        anchor = Self.position(w); glass = anchor
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: w, queue: .main) { [weak self] _ in
            self?.windowMoved()
        }
    }

    private static func position(_ w: NSWindow) -> CGPoint { CGPoint(x: w.frame.minX, y: -w.frame.minY) }

    private func windowMoved() {
        guard let w = window else { return }
        anchor = Self.position(w)
        let wobble = Prefs.shared.appearance.wobble, held = Self.mouseHeld()
        guard !paused, wobble > 0, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return settle() }
        guard held else {
            // Let go but still moving: the drag's last catch-up, or macOS pushing the window back inside the screen
            // at an edge or corner. The glass is springing already — let it chase the new spot instead of freezing.
            // Not springing (re-centred, moved to another screen): just snap.
            if link != nil { return }
            return settle()
        }
        // Held: rigid, and any move is the drag, however big (fast throws coalesce into large steps).
        // The drop's momentum is measured from the pointer each frame (see `step`), since macOS moves the window
        // itself during a drag and reports the moves late.
        dragging = true
        glass = anchor; velocity = .zero
        if lag != .zero { lag = .zero }
        startLink()
    }

    private func startLink() {
        guard link == nil, let w = window else { return }
        lastStep = 0
        let l = w.displayLink(target: self, selector: #selector(step(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func step(_ l: CADisplayLink) {
        let now = l.timestamp
        let dt = lastStep == 0 ? 1.0 / 120 : min(now - lastStep, 1.0 / 30)
        lastStep = now
        if dragging {
            guard !Self.mouseHeld() else {   // still held: stay solid, and follow the pointer's speed (a pause decays it)
                let m = NSEvent.mouseLocation
                if let last = lastMouse {
                    let k = 0.3, vx = (m.x - last.x) / dt, vy = -(m.y - last.y) / dt   // y down, like `anchor`
                    dragVelocity = CGVector(dx: dragVelocity.dx * (1 - k) + vx * k, dy: dragVelocity.dy * (1 - k) + vy * k)
                }
                lastMouse = m
                return
            }
            lastMouse = nil
            drop()
        }
        let wobble = min(max(Prefs.shared.appearance.wobble, 0.1), 2)
        // High friction: damping ratio 0.5 whatever the wobble setting, so a drop swings once, bounces back a
        // little, and stops (≤ 2 visible swings, settled in ~0.5 s). The setting only scales how far it swings.
        let stiffness = 420 / max(wobble, 0.5).squareRoot()
        let damping = 2 * 0.5 * stiffness.squareRoot()
        for _ in 0..<2 {   // two half-steps keep the spring stable at any frame rate
            let h = dt / 2
            let ax = stiffness * (anchor.x - glass.x) - damping * velocity.dx
            let ay = stiffness * (anchor.y - glass.y) - damping * velocity.dy
            velocity.dx += ax * h; velocity.dy += ay * h
            glass.x += velocity.dx * h; glass.y += velocity.dy * h
        }
        let raw = CGSize(width: glass.x - anchor.x, height: glass.y - anchor.y)
        let m = Self.maxLag * min(wobble, 1.5)
        lag = CGSize(width: m * tanh(raw.width / m), height: m * tanh(raw.height / m))   // soft limit, no hard stop
        if abs(raw.width) < 0.05, abs(raw.height) < 0.05, hypot(velocity.dx, velocity.dy) < 1 { settle() }
    }

    /// Let go: the glass keeps some of the drag's momentum and dips as if set down, then the spring takes over.
    private func drop() {
        dragging = false
        let wobble = min(max(Prefs.shared.appearance.wobble, 0.1), 2)
        let carry = 0.175 * wobble, cap = 450.0
        velocity = CGVector(dx: max(min(dragVelocity.dx * carry, cap), -cap),
                            dy: max(min(dragVelocity.dy * carry, cap), -cap) + 80 * wobble)
        dragVelocity = .zero
    }

    private func settle() {
        link?.invalidate(); link = nil
        dragging = false
        glass = anchor; velocity = .zero; dragVelocity = .zero
        if lag != .zero { lag = .zero }
    }

    deinit { observer.map(NotificationCenter.default.removeObserver); link?.invalidate() }
}

/// Trails the window by `lag` and stretches along the motion, squashing across it.
struct Jelly: ViewModifier {
    @ObservedObject var motion: JellyMotion
    func body(content: Content) -> some View {
        let l = motion.lag, k: CGFloat = 1 / 520
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

/// Drag area: dragging here moves the window (with the jelly). Laid behind a window's content it makes every
/// empty spot a handle; controls in front keep their clicks.
/// `forwardsScroll`: scrolls over the strip go to the window's main scroll view (a pinned header over a list).
struct WindowDragArea: NSViewRepresentable {
    var forwardsScroll = false
    final class DragView: NSView {
        var forwardsScroll = false
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }   // drag a window that isn't in front yet
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
        }
        override func scrollWheel(with event: NSEvent) {
            guard forwardsScroll, let root = window?.contentView, let target = Self.largestScrollView(in: root) else {
                return super.scrollWheel(with: event)
            }
            target.scrollWheel(with: event)
        }
        private static func largestScrollView(in v: NSView) -> NSScrollView? {
            var best: NSScrollView?
            func walk(_ v: NSView) {
                if let s = v as? NSScrollView, !s.isHiddenOrHasHiddenAncestor, s.hasVerticalScroller || s.documentView != nil,
                   s.frame.width * s.frame.height > (best.map { $0.frame.width * $0.frame.height } ?? 0) { best = s }
                v.subviews.forEach(walk)
            }
            walk(v)
            return best
        }
    }
    func makeNSView(context: Context) -> NSView { let v = DragView(); v.forwardsScroll = forwardsScroll; return v }
    func updateNSView(_ v: NSView, context: Context) {}
}

/// Lays the grips out along the glass, which sits the window's `margin` inside it.
/// Corner grips reach in past the rounded corner's curve: the square corner itself is clear space, and clicks on
/// clear space go through the window to whatever is behind it.
private final class GripContainer: NSView {
    private var corners: AnyCancellable?
    override init(frame: NSRect) {
        super.init(frame: frame)
        corners = Prefs.shared.$appearance.map(\.radius).removeDuplicates().sink { [weak self] _ in self?.needsLayout = true }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let m = (window as? GlassWindow)?.margin ?? JellyMotion.margin
        let glass = bounds.insetBy(dx: m, dy: m)
        // Edge thickness (half in, half out); corner reach inside the glass (a round corner's curve is ~0.29 × radius
        // in from the square corner; stops short of the window buttons); corner overhang outside.
        let t: CGFloat = 10, c = max(18, Prefs.shared.appearance.radius * 0.29 + 8), o: CGFloat = 9
        for case let g as ResizeGrip in subviews {
            let e = g.edges
            var r = NSRect.zero
            if e == .left { r = NSRect(x: glass.minX - t / 2, y: glass.minY + c, width: t, height: glass.height - 2 * c) }
            if e == .right { r = NSRect(x: glass.maxX - t / 2, y: glass.minY + c, width: t, height: glass.height - 2 * c) }
            if e == .top { r = NSRect(x: glass.minX + c, y: glass.maxY - t / 2, width: glass.width - 2 * c, height: t) }
            if e == .bottom { r = NSRect(x: glass.minX + c, y: glass.minY - t / 2, width: glass.width - 2 * c, height: t) }
            if e.count == 2 {
                let x = e.contains(.left) ? glass.minX - o : glass.maxX - c
                let y = e.contains(.bottom) ? glass.minY - o : glass.maxY - c
                r = NSRect(x: x, y: y, width: c + o, height: c + o)
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
