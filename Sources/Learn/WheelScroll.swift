import AppKit

/// ⌘↑ / ⌘↓ anywhere: the scroll wheel at the pointer. ⌘← / ⌘→ scroll sideways unless you're typing (then they're
/// start / end of line); ⌘ + Space held + any arrow scrolls even then. Holding
/// speeds it up from 1 to 100 px a frame (ease in-out over `ramp` s); letting go eases it out back to 1 over `fall` s,
/// then it stops. ⌘Space let go without an arrow still opens Learn — on release instead of press.
/// Main-thread only (Learn's key tap).
final class WheelScroll {
    enum Direction { case up, down, left, right }
    static let ramp = 2.5, fall = 0.4
    private static let slow = 1.0, fast = 100.0

    var ownsSpace: () -> Bool = { false }   // ⌘Space is Learn's panel key (Spotlight's is left alone)
    var spaceTapped: () -> Void = {}        // ⌘Space let go with no arrow: open / close the panel
    private var spaceDown = false, spaceUsed = false

    private var key: Int?   // the arrow being held
    private var dir = Direction.up
    private var heldSince = Date()
    private var releasedAt: Date?, releaseSpeed = slow
    private var carry = 0.0   // sub-pixel distance not posted yet
    private var posted = 0    // px this scroll, for the debug log
    private var timer: Timer?

    static func speed(held t: Double) -> Double {
        let x = min(max(t / ramp, 0), 1)
        return slow + (fast - slow) * x * x * (3 - 2 * x)   // smoothstep
    }

    /// nil once it has stopped.
    static func coast(from v: Double, after t: Double) -> Double? {
        guard t < fall else { return nil }
        let x = t / fall
        return slow + (v - slow) * (1 - x) * (1 - x)   // ease out
    }

    /// ⌘ + ↑ ↓ always; ← → unless typing in text, where ⌘← / ⌘→ are start / end of line (⌘Space + ← → still scroll).
    static func direction(code: Int, spaceHeld: Bool, inText: Bool) -> Direction? {
        switch code {
        case 126: .up
        case 125: .down
        case 123 where spaceHeld || !inText: .left
        case 124 where spaceHeld || !inText: .right
        default: nil
        }
    }

    /// Key tap hook (press and release); true = the key was ours.
    func handle(code: Int, mods: Mods, down: Bool) -> Bool {
        if code == 49 { return space(mods: mods, down: down) }
        guard down else {   // by key, not direction: Space may already be up when ← comes up
            guard key == code else { return false }
            key = nil
            releaseSpeed = Self.speed(held: Date().timeIntervalSince(heldSince))
            Debug.log("wheel release after \(String(format: "%.2f", Date().timeIntervalSince(heldSince)))s, \(posted) px so far")
            releasedAt = Date()
            return true
        }
        let sideways = (code == 123 || code == 124) && !spaceDown && key != code   // repeats: already decided
        guard mods == [.cmd], let d = Self.direction(code: code, spaceHeld: spaceDown, inText: sideways && ElementScanner.typingInText())
        else { return false }
        spaceUsed = spaceUsed || spaceDown
        if key != code {   // a fresh press (repeats just keep it going)
            key = code
            dir = d
            Debug.log("wheel \(d) front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?") at=\(CGEvent(source: nil)?.location ?? .zero)")
            heldSince = Date()
            releasedAt = nil
            if timer == nil {
                carry = 0; posted = 0
                timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
                RunLoop.main.add(timer!, forMode: .common)
            }
        }
        return true
    }

    /// ⌘Space is held back until it's let go: an arrow in between makes it the scroll chord.
    private func space(mods: Mods, down: Bool) -> Bool {
        guard down else {
            guard spaceDown else { return false }
            spaceDown = false
            if !spaceUsed { spaceTapped() }
            return true
        }
        guard spaceDown || (mods == [.cmd] && ownsSpace()) else { return false }
        if !spaceDown { spaceDown = true; spaceUsed = false }   // repeats: still held
        return true
    }

    private func tick() {
        let now = Date()
        guard let v = releasedAt.map({ Self.coast(from: releaseSpeed, after: now.timeIntervalSince($0)) })
                ?? Self.speed(held: now.timeIntervalSince(heldSince)) else {
            timer?.invalidate(); timer = nil
            return
        }
        carry += v
        let px = Int32(carry)
        carry -= Double(px)
        guard px > 0 else { return }
        posted += Int(px)
        let (v1, v2): (Int32, Int32) = switch dir { case .up: (px, 0); case .down: (-px, 0); case .left: (0, px); case .right: (0, -px) }
        let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: v1, wheel2: v2, wheel3: 0)
        e?.flags = []   // ⌘ is still held: ⌘ + wheel zooms (VS Code)
        e?.post(tap: .cghidEventTap)   // goes to whatever is under the pointer
    }
}
