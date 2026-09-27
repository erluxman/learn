import AppKit

/// Keyboard mouse: while on, keys move the real pointer, click, drag and scroll. ⌘/⌃ combos and unmapped keys
/// still reach the app. Main-thread only (driven by Learn's key tap).
final class PointerMode {
    private(set) var active = false
    var onKeysCaptured: (Bool) -> Void = { _ in }   // tells the key tap to route keys (and releases) here

    private var held: Set<Int> = []   // direction keys currently down
    private var heldSince = Date()
    private var carry = CGPoint.zero   // sub-pixel motion not posted yet (the slow start moves under 1px a tick)
    private var timer: Timer?
    private var dragging = false
    private let src = CGEventSource(stateID: .hidSystemState)
    private var lastSpot: [CGDirectDisplayID: CGPoint] = [:]   // where the pointer was on each screen

    // H/←, L/→, K/↑, J/↓
    private static let left: Set<Int> = [4, 123], right: Set<Int> = [37, 124], up: Set<Int> = [40, 126], down: Set<Int> = [38, 125]
    private static let moves = left.union(right).union(up).union(down)
    private static let help = "HJKL / arrows move · ⇧ slow · ⌥ scroll · Space click · D double · R right-click · V drag · same key again: next screen · ⎋ exit"

    func toggle() { active ? stop() : start() }

    func start() {
        guard !active else { return }
        active = true
        held = []
        onKeysCaptured(true)
        KeyHUD.shared.setSticky("Pointer mode", caption: Self.help)
    }

    func stop() {
        guard active else { return }
        if dragging { toggleDrag() }
        timer?.invalidate(); timer = nil
        held = []
        active = false
        onKeysCaptured(false)
        KeyHUD.shared.setSticky(nil)
    }

    /// Returns true when the key was used.
    func handle(keyCode code: Int, mods: Mods, isRepeat: Bool) -> Bool {
        if code == 53 && mods.isEmpty { stop(); return true }
        if isToggleKey(code, mods) { if !isRepeat { Self.displays().count > 1 ? nextScreen() : stop() }; return true }
        guard mods.isSubset(of: [.shift, .opt]) else { return false }   // ⌘C, ⌃Tab… go to the app
        if Self.moves.contains(code) {
            if held.isEmpty {
                heldSince = Date()
                carry = .zero
                timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
                RunLoop.main.add(timer!, forMode: .common)
            }
            if held.insert(code).inserted { tick() }   // a quick tap still moves
            return true
        }
        switch code {
        case 49, 36: if !isRepeat { dragging ? toggleDrag() : click(.left) }   // Space / ↩ (drops while dragging)
        case 2: if !isRepeat { click(.left, count: 2) }                         // D
        case 15: if !isRepeat { click(.right); stop() }                         // R: the menu needs the arrow keys
        case 9: if !isRepeat { toggleDrag() }                                    // V
        default: return false
        }
        return true
    }

    func release(_ code: Int) {
        guard held.remove(code) != nil, held.isEmpty else { return }
        timer?.invalidate(); timer = nil
    }

    private func isToggleKey(_ code: Int, _ mods: Mods) -> Bool {
        Bindings.shared.globals.first { $0.path == LearnActions.pointer }?.matches(code, mods) == true
    }

    // MARK: Motion

    /// Speed per tick after holding a direction key `t` seconds: an accelerator pedal. Ease-in (cubic), so a tap barely
    /// nudges, holding keeps pressing harder, and full speed comes after `rampUp`. Letting go stops dead.
    private static let rampUp = 1.0
    private static func speed(_ t: Double, from lo: Double, to hi: Double) -> Double {
        let p = min(t / rampUp, 1)
        return lo + (hi - lo) * p * p * p
    }

    /// 60 Hz while a direction key is held; ⇧ = 1px steps, ⌥ = scroll instead.
    private func tick() {
        var dx = 0.0, dy = 0.0
        if !held.isDisjoint(with: Self.left) { dx -= 1 }
        if !held.isDisjoint(with: Self.right) { dx += 1 }
        if !held.isDisjoint(with: Self.up) { dy -= 1 }
        if !held.isDisjoint(with: Self.down) { dy += 1 }
        guard dx != 0 || dy != 0 else { return }
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let t = Date().timeIntervalSince(heldSince)
        if flags.contains(.maskAlternate) {
            let s = Self.speed(t, from: 2, to: 30)
            // Positive wheel values scroll toward the top / left.
            CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 2,
                    wheel1: Int32(-dy * s), wheel2: Int32(-dx * s), wheel3: 0)?.post(tap: .cghidEventTap)
            return
        }
        let s = flags.contains(.maskShift) ? 1 : Self.speed(t, from: 0.5, to: 40)   // 30 → 2,400 px/s
        carry.x += dx * s; carry.y += dy * s
        let step = CGPoint(x: carry.x.rounded(.towardZero), y: carry.y.rounded(.towardZero))
        carry.x -= step.x; carry.y -= step.y
        guard step != .zero, let from = CGEvent(source: nil)?.location else { return }
        post(dragging ? .leftMouseDragged : .mouseMoved, at: Self.clamp(CGPoint(x: from.x + step.x, y: from.y + step.y), from: from))
    }

    /// Keep the pointer on a display; at an edge, slide along it.
    private static func clamp(_ p: CGPoint, from: CGPoint) -> CGPoint {
        let screens = displays().map { CGDisplayBounds($0).insetBy(dx: 0.5, dy: 0.5) }
        for c in [p, CGPoint(x: p.x, y: from.y), CGPoint(x: from.x, y: p.y)] where screens.contains(where: { $0.contains(c) }) { return c }
        return from
    }

    /// Active displays, left to right (top to bottom when stacked).
    private static func displays() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), n: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &n)
        return ids.prefix(Int(n)).sorted {
            let a = CGDisplayBounds($0), b = CGDisplayBounds($1)
            return (a.minX, a.minY) < (b.minX, b.minY)
        }
    }

    /// Jump to the next screen (wrapping): back to where the pointer last was there, else its centre.
    private func nextScreen() {
        guard let from = CGEvent(source: nil)?.location else { return }
        let ids = Self.displays()
        let i = ids.firstIndex { CGDisplayBounds($0).contains(from) } ?? 0
        lastSpot[ids[i]] = from
        let next = ids[(i + 1) % ids.count], b = CGDisplayBounds(next)
        let to = lastSpot[next].flatMap { b.contains($0) ? $0 : nil } ?? CGPoint(x: b.midX, y: b.midY)
        post(dragging ? .leftMouseDragged : .mouseMoved, at: to)
    }

    // MARK: Buttons

    private func click(_ button: CGMouseButton, count: Int = 1) {
        guard let p = CGEvent(source: nil)?.location else { return }
        let (down, up): (CGEventType, CGEventType) = button == .right ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
        for n in 1...count {   // click count per press: Chromium ignores clicks without one, double-click needs 2
            post(down, at: p, button: button, clicks: n)
            usleep(30_000)
            post(up, at: p, button: button, clicks: n)
        }
    }

    private func toggleDrag() {
        guard let p = CGEvent(source: nil)?.location else { return }
        dragging.toggle()
        post(dragging ? .leftMouseDown : .leftMouseUp, at: p)
        KeyHUD.shared.setSticky(dragging ? "Dragging" : "Pointer mode", caption: dragging ? "Move, then V or Space to drop" : Self.help)
    }

    private func post(_ type: CGEventType, at p: CGPoint, button: CGMouseButton = .left, clicks: Int = 1) {
        let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: button)
        e?.setIntegerValueField(.mouseEventClickState, value: Int64(clicks))
        e?.post(tap: .cghidEventTap)
    }
}
