import AppKit

/// Click-through layer over all screens that draws hint labels or a highlight box at AX-coordinate rects.
final class Overlay {
    struct Mark { let frame: CGRect; let label: String?; let typed: Int; var alt = false }   // frame in AX coords (top-left origin); alt = right-click mode

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
            if let label = m.label { drawLabel(label, typed: m.typed, alt: m.alt, at: r) } else { drawHighlight(r) }
        }
    }

    private func drawHighlight(_ r: NSRect) {
        let p = NSBezierPath(roundedRect: r.insetBy(dx: -3, dy: -3), xRadius: 6, yRadius: 6)
        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill(); p.fill()
        NSColor.controlAccentColor.setStroke(); p.lineWidth = 3; p.stroke()
    }

    private func drawLabel(_ label: String, typed: Int, alt: Bool, at r: NSRect) {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        let s = NSMutableAttributedString(string: label, attributes: [.font: font, .foregroundColor: NSColor.black])
        s.addAttribute(.foregroundColor, value: NSColor.black.withAlphaComponent(0.35), range: NSRange(location: 0, length: min(typed, label.count)))
        let size = s.size()
        let box = NSRect(x: r.minX, y: r.maxY - size.height - 2, width: size.width + 8, height: size.height + 2)
        let p = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
        (alt ? NSColor(calibratedRed: 0.55, green: 0.8, blue: 1, alpha: 0.95)      // blue = right-click
             : NSColor(calibratedRed: 1, green: 0.85, blue: 0.2, alpha: 0.95)).setFill(); p.fill()
        NSColor.black.withAlphaComponent(0.5).setStroke(); p.lineWidth = 1; p.stroke()
        s.draw(at: NSPoint(x: box.minX + 4, y: box.minY + 1))
    }
}

/// Label mode: letters over every clickable element of the front app; type a label to click it.
final class HintMode {
    private let overlay = Overlay()
    private var items: [(label: String, element: ScreenElement)] = []
    private var typed = ""
    private var rightClick = false   // Tab toggles: next completed label right-clicks
    private var pid: pid_t = 0
    var active: Bool { !items.isEmpty }
    var onKeysCaptured: (Bool) -> Void = { _ in }   // tells the key tap to route keys here

    private static let alphabet = Array("ASDFJKLGHQWERUIOPTYZXCVBNM")

    func toggle() { active ? stop() : start() }

    func start() {
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        pid = app.processIdentifier
        DispatchQueue.global(qos: .userInteractive).async {
            let els = ElementScanner.scan(pid: self.pid)
            DispatchQueue.main.async {
                guard !els.isEmpty else { NSSound.beep(); return }
                let labels = Self.labels(els.count)
                self.items = zip(labels, els).map { ($0, $1) }
                self.typed = ""
                self.rightClick = false
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
        if keyCode == 48 { rightClick.toggle(); render(); return true }                // ⇥ = right-click mode
        guard mods.isEmpty, let k = Keys.names[keyCode], k.count == 1, let c = k.first, c.isLetter else { stop(); return true }
        let next = typed + String(c)
        let matches = items.filter { $0.label.hasPrefix(next) }
        guard !matches.isEmpty else { NSSound.beep(); return true }
        typed = next
        if matches.count == 1, matches[0].label == next {
            let e = matches[0].element
            let right = rightClick
            stop()
            right ? ElementScanner.showMenu(e) : ElementScanner.perform(e)
        } else {
            render()
        }
        return true
    }

    private func render() {
        overlay.show(items.filter { $0.label.hasPrefix(typed) }
            .map { Overlay.Mark(frame: $0.element.frame, label: $0.label, typed: typed.count, alt: rightClick) })
    }

    /// Same-length labels so none is a prefix of another; home row first.
    private static func labels(_ n: Int) -> [String] {
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
