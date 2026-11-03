import AppKit

/// Click-through layer over all screens that draws hint labels or a highlight box at AX-coordinate rects.
final class Overlay {
    struct Mark { let frame: CGRect; let label: String?; let typed: Int; var alt = false; var at: CGPoint? = nil }   // AX coords (top-left origin); alt = right-click mode; at = label's top-left (`place`)

    static let labelFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)

    /// A label's box: its text plus padding.
    static func labelSize(_ label: String) -> CGSize {
        let s = (label as NSString).size(withAttributes: [.font: labelFont])
        return CGSize(width: s.width + 8, height: s.height + 2)
    }

    /// Ring offsets (in label-sized steps) around a label's own spot, nearest first, below / right before above / left.
    private static let offsets: [(Int, Int)] = {
        let all: [(Int, Int)] = (-4...4).flatMap { dy in (-4...4).map { dx in (dx, dy) } }
        func key(_ o: (Int, Int)) -> (Int, Int, Int) { (o.0 * o.0 + o.1 * o.1, -o.1, -o.0) }
        return all.sorted { key($0) < key($1) }
    }()

    /// Label positions (top-left) that don't overlap: each takes its own spot, or the nearest free one up to 4 label
    /// sizes away (else its own spot). ponytail: greedy, n² — fine for a few hundred labels.
    static func place(_ boxes: [(anchor: CGPoint, size: CGSize)]) -> [CGPoint] {
        var taken: [CGRect] = []
        return boxes.map { b in
            let spot = offsets.lazy.map { CGPoint(x: b.anchor.x + CGFloat($0.0) * (b.size.width + 2), y: b.anchor.y + CGFloat($0.1) * (b.size.height + 2)) }
                .first { p in !taken.contains { $0.intersects(CGRect(origin: p, size: b.size)) } } ?? b.anchor
            taken.append(CGRect(origin: spot, size: b.size))
            return spot
        }
    }

    private var windows: [NSWindow] = []

    func show(_ marks: [Mark]) {
        if windows.count != NSScreen.screens.count { build() }
        for w in windows {
            (w.contentView as? MarksView)?.marks = marks
            w.contentView?.needsDisplay = true
            w.orderFrontRegardless()
        }
    }

    func hide() { windows.forEach { $0.orderOut(nil) } }

    private func build() {
        hide()
        windows = NSScreen.screens.map { screen in
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            w.setFrame(screen.frame, display: false)
            w.contentView = MarksView(frame: NSRect(origin: .zero, size: screen.frame.size))
            return w
        }
    }
}

private final class MarksView: NSView {
    var marks: [Overlay.Mark] = []

    override func draw(_ dirtyRect: NSRect) {
        guard let win = window, let primary = NSScreen.screens.first else { return }
        for m in marks {
            // AX (top-left of primary screen) → Cocoa global → this window's coords
            let global = NSRect(x: m.frame.minX, y: primary.frame.height - m.frame.maxY, width: m.frame.width, height: m.frame.height)
            let r = global.offsetBy(dx: -win.frame.minX, dy: -win.frame.minY)
            guard r.intersects(bounds) else { continue }
            if let label = m.label {
                let at = m.at.map { NSPoint(x: $0.x - win.frame.minX, y: primary.frame.height - $0.y - win.frame.minY) }   // AX top-left → this window
                drawLabel(label, typed: m.typed, alt: m.alt, topLeft: at ?? NSPoint(x: r.minX, y: r.maxY))
            } else { drawHighlight(r) }
        }
    }

    private func drawHighlight(_ r: NSRect) {
        let p = NSBezierPath(roundedRect: r.insetBy(dx: -3, dy: -3), xRadius: 6, yRadius: 6)
        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill(); p.fill()
        NSColor.controlAccentColor.setStroke(); p.lineWidth = 3; p.stroke()
    }

    private func drawLabel(_ label: String, typed: Int, alt: Bool, topLeft p: NSPoint) {
        let s = NSMutableAttributedString(string: label, attributes: [.font: Overlay.labelFont, .foregroundColor: NSColor.black])
        s.addAttribute(.foregroundColor, value: NSColor.black.withAlphaComponent(0.35), range: NSRange(location: 0, length: min(typed, label.count)))
        let size = Overlay.labelSize(label)
        let box = NSRect(x: p.x, y: p.y - size.height, width: size.width, height: size.height)
        let p = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
        (alt ? NSColor(calibratedRed: 0.55, green: 0.8, blue: 1, alpha: 0.95)      // blue = right-click
             : NSColor(calibratedRed: 1, green: 0.85, blue: 0.2, alpha: 0.95)).setFill(); p.fill()
        NSColor.black.withAlphaComponent(0.5).setStroke(); p.lineWidth = 1; p.stroke()
        s.draw(at: NSPoint(x: box.minX + 4, y: box.minY + 1))
    }
}

/// Label mode: letters over every clickable element on every screen; type a label to click it.
final class HintMode {
    private let overlay = Overlay()
    private var items: [(label: String, element: ScreenElement, at: CGPoint)] = []   // at: placed once, so labels don't jump while typing
    private var typed = ""
    // Before the first letter: Space = right-click, Space Space = grab (hold the button down there, then drag it with
    // the arrows or the mouse), M = the pointer goes there too, ⌘M = pointer goes there, pointer mode on
    private var rightClick = false, grab = false, movePointer = false, pointerMode = false
    var active: Bool { !items.isEmpty }
    var onKeysCaptured: (Bool) -> Void = { _ in }   // tells the key tap to route keys here
    var onPointerMode: () -> Void = {}
    var onAdjust: (ScreenElement) -> Void = { _ in }   // a slider / stepper's label: adjust mode
    var onGrab: (CGPoint) -> Void = { _ in }

    private static let alphabet = Array("ASDFJKLGHQWERUIOPTYZXCVBN")   // no M: it's the pointer prefix

    func toggle() { active ? stop() : start() }

    /// Labels every visible window on every display, so any screen is one label away.
    func start() {
        DispatchQueue.global(qos: .userInteractive).async {
            let els = ElementScanner.scanVisible()
            DispatchQueue.main.async {
                guard !els.isEmpty else { NSSound.beep(); return }
                let labels = Self.labels(els.count)
                let at = Overlay.place(zip(labels, els).map { (CGPoint(x: $1.frame.minX, y: $1.frame.minY), Overlay.labelSize($0)) })
                self.items = labels.indices.map { (labels[$0], els[$0], at[$0]) }
                self.typed = ""
                self.rightClick = false; self.grab = false; self.movePointer = false; self.pointerMode = false
                self.render()
                self.onKeysCaptured(true)
            }
        }
    }

    func stop() {
        items = []
        typed = ""
        overlay.hide()
        onKeysCaptured(false)
    }

    /// Returns true when the key was used. Esc/any non-letter ends label mode.
    func handle(keyCode: Int, mods: Mods) -> Bool {
        if keyCode == 51 { typed = String(typed.dropLast()); render(); return true }   // ⌫
        if keyCode == 48 { rightClick.toggle(); grab = false; render(); return true }   // ⇥ = right-click mode
        if keyCode == 49 && typed.isEmpty {   // Space: right-click → Space Space: grab → again: plain click
            (rightClick, grab) = rightClick ? (false, true) : grab ? (false, false) : (true, false)
            if grab { KeyHUD.shared.flash("Space Space", caption: "Grab: then drag with the arrows or the mouse", force: true) }
            render()
            return true
        }
        if keyCode == 46 && typed.isEmpty && (mods.isEmpty || mods == [.cmd]) {   // M / ⌘M
            if mods.isEmpty { movePointer.toggle() } else { pointerMode.toggle() }
            KeyHUD.shared.flash(mods.isEmpty ? "M" : "⌘M", caption: pointerMode ? "Pointer mode there" : movePointer ? "Pointer goes there" : "Pointer stays", force: true)
            return true
        }
        guard mods.isEmpty, let k = Keys.names[keyCode], k.count == 1, let c = k.first, c.isLetter else { stop(); return true }
        let next = typed + String(c)
        let matches = items.filter { $0.label.hasPrefix(next) }
        guard !matches.isEmpty else { NSSound.beep(); return true }
        typed = next
        if matches.count == 1, matches[0].label == next {
            let e = matches[0].element
            let (right, move, pointer) = (rightClick, movePointer, pointerMode)
            stop()
            if grab { return grabbed(e) }
            if move || pointer { ElementScanner.movePointer(to: e) }   // first, so a real click doesn't put it back
            if pointer { onPointerMode(); return true }
            if !right, AdjustMode.adjustable(e) { onAdjust(e); return true }
            DispatchQueue.global(qos: .userInteractive).async {   // another app's window (maybe another screen): to the front first
                ElementScanner.bringToFront(e)
                right ? ElementScanner.showMenu(e) : ElementScanner.perform(e)
            }
        } else {
            render()
        }
        return true
    }

    /// Space Space + label: pointer onto it, button down, pointer mode dragging it.
    private func grabbed(_ e: ScreenElement) -> Bool {
        let p = CGPoint(x: e.frame.midX, y: e.frame.midY)
        DispatchQueue.global(qos: .userInteractive).async {
            ElementScanner.bringToFront(e)   // the first click into an inactive Chromium window only activates it
            DispatchQueue.main.async { self.onGrab(p) }
        }
        return true
    }

    private func render() {
        overlay.show(items.filter { $0.label.hasPrefix(typed) }
            .map { Overlay.Mark(frame: $0.element.frame, label: $0.label, typed: typed.count, alt: rightClick, at: $0.at) })
    }

    /// Same-length labels so none is a prefix of another; home row first.
    static func labels(_ n: Int) -> [String] {
        let a = alphabet.map(String.init)
        var len = 1, cap = a.count
        while cap < n { len += 1; cap *= a.count }
        var out = [""]
        for _ in 0..<len { out = out.flatMap { p in a.map { p + $0 } } }
        return Array(out.prefix(n))
    }

    // Highlight for Learn's list selection (no labels).
    func highlight(_ frame: CGRect?) {
        guard !active else { return }
        if let frame { overlay.show([Overlay.Mark(frame: frame, label: nil, typed: 0)]) } else { overlay.hide() }
    }
}
