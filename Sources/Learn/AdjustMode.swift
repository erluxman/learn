import AppKit

/// Adjust mode: a slider or stepper picked by label (or ↵ in Learn's list) takes the keys. ←→ / HJKL step it, ⇧ ten
/// steps, 0–9 jump to 0–90 %, $ to the top, ↵ / ⎋ done. Values only ever move by steps: web sliders report success
/// for a written value but ignore it.
final class AdjustMode {
    enum Action: Equatable { case step(Int), percent(Double), done }

    private(set) var active = false
    var onKeysCaptured: (Bool) -> Void = { _ in }   // tells the key tap to route keys here
    private var target: ScreenElement?
    private let queue = DispatchQueue(label: "learn.adjust")   // AX calls in key order, off the key tap

    static func adjustable(_ e: ScreenElement) -> Bool { e.role == "AXSlider" || e.role == "AXIncrementor" }

    func start(_ e: ScreenElement) {
        target = e
        active = true
        onKeysCaptured(true)
        if e.web {   // its steps are arrow keys: the slider needs the keyboard
            queue.async {
                ElementScanner.bringToFront(e)
                AXUIElementSetAttributeValue(e.ref, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            }
        }
        show()
    }

    func stop() {
        guard active else { return }
        active = false
        target = nil
        onKeysCaptured(false)
        KeyHUD.shared.setSticky(nil)
    }

    /// Returns true when the key was used. Any other key ends adjust mode and goes on to the app.
    func handle(keyCode: Int, mods: Mods) -> Bool {
        guard let e = target else { return false }
        guard let a = Self.action(keyCode: keyCode, mods: mods) else { stop(); return false }
        switch a {
        case .done: stop(); return true
        case .step(let n): queue.async { for _ in 0..<abs(n) { Self.step(e, up: n > 0) } }
        case .percent(let p): queue.async { Self.jump(e, to: p) }
        }
        queue.async { DispatchQueue.main.async { self.show() } }
        return true
    }

    private static let digits = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25]   // 0…9

    static func action(keyCode k: Int, mods: Mods) -> Action? {
        if mods == [.shift], k == 21 { return .percent(1) }   // $
        guard mods.isEmpty || mods == [.shift] else { return nil }
        let n = mods.isEmpty ? 1 : 10
        switch k {
        case 124, 126, 37, 40: return .step(n)     // → ↑ L K
        case 123, 125, 4, 38: return .step(-n)     // ← ↓ H J
        case 36, 53: return .done                  // ↵ ⎋
        default: return mods.isEmpty ? digits.firstIndex(of: k).map { .percent(Double($0) / 10) } : nil
        }
    }

    /// `p` of the way from the slider's minimum to its maximum: big AX steps first, then the slider's own steps.
    static func jump(_ e: ScreenElement, to p: Double) {
        guard let lo = number(e.ref, kAXMinValueAttribute), let hi = number(e.ref, kAXMaxValueAttribute) else { return }
        let goal = lo + (hi - lo) * p, read = { number(e.ref, kAXValueAttribute) }
        if e.web { approach(goal, read: read, step: { axStep(e.ref, up: $0) }) }
        approach(goal, read: read, step: { step(e, up: $0) })
    }

    /// Steps toward `goal` until it's crossed or the value stops moving; ends on whichever side is nearer.
    static func approach(_ goal: Double, read: () -> Double?, step: (Bool) -> Void) {
        guard var cur = read() else { return }
        let up = goal > cur
        for _ in 0..<1000 {
            if up ? cur >= goal : cur <= goal { return }
            step(up)
            guard let next = read(), next != cur else { return }
            if up ? next > goal : next < goal {
                if abs(cur - goal) < abs(next - goal) { step(!up) }
                return
            }
            cur = next
        }
    }

    /// One of the slider's own steps. Web sliders: the arrow key itself (Chromium's AX step is a sixth of the range —
    /// Obsidian's −3…3 slider moves by 1, its arrow key by 0.1). Elsewhere: AX increment / decrement.
    static func step(_ e: ScreenElement, up: Bool) {
        guard e.web else { return axStep(e.ref, up: up) }
        let before = number(e.ref, kAXValueAttribute), pid = ElementScanner.pid(e)
        for down in [true, false] {
            let k = CGEvent(keyboardEventSource: nil, virtualKey: up ? 124 : 123, keyDown: down)
            k?.setIntegerValueField(.eventSourceUserData, value: KeyTap.ownKey)
            k?.postToPid(pid)
        }
        settle(e.ref, from: before)
    }

    private static func axStep(_ el: AXUIElement, up: Bool) {
        let before = number(el, kAXValueAttribute)
        AXUIElementPerformAction(el, (up ? kAXIncrementAction : kAXDecrementAction) as CFString)
        settle(el, from: before)
    }

    /// Wait (≤500 ms) for the value to show the step: Chromium updates it a moment later, and a step taken before
    /// that starts from the old value.
    private static func settle(_ el: AXUIElement, from before: Double?) {
        for _ in 0..<33 where number(el, kAXValueAttribute) == before { usleep(15_000) }
    }

    static func number(_ el: AXUIElement, _ attr: String) -> Double? {
        var v: AnyObject?
        AXUIElementCopyAttributeValue(el, attr as CFString, &v)
        return (v as? NSNumber)?.doubleValue
    }

    private func show() {
        guard let e = target else { return }
        let v = Self.number(e.ref, kAXValueAttribute).map { String(format: "%g", $0) } ?? ""
        KeyHUD.shared.setSticky("\(e.text.isEmpty ? "Adjust" : e.text)  \(v)", caption: "←→ / HJKL step · ⇧ ×10 · 0–9 jump to % · $ max · ↵ done")
    }
}
