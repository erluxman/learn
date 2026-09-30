import AppKit

/// Settings ▸ General ▸ "Turn off mouse & trackpad": swallows every pointer event from the hardware (moves, clicks,
/// scrolls, trackpad gestures) so shortcuts are the only way around. Events Learn posts itself (pointer mode,
/// clicking what you typed) still go through. Its hotkey (⌃⌥⌘M by default) turns it back on from the keyboard.
/// Main-thread only.
final class PointerBlock {
    static let shared = PointerBlock()
    private var tap: CFMachPort?

    /// Pointer event types, as raw values (gesture types have no CGEventType case).
    private static let types: [UInt32] = [
        1, 2, 3, 4, 5, 6, 7, 22, 25, 26, 27,   // left/right down, up, mouse moved, dragged, scroll, other down/up/dragged
        18, 19, 20, 29, 30, 31, 32, 34,        // rotate, begin/end gesture, gesture, magnify, swipe, smart magnify, pressure
    ]

    /// Starts or stops blocking to match `Prefs.blockPointer`.
    func update() {
        let on = Prefs.shared.blockPointer
        if on, tap == nil { start() }
        if let tap { CGEvent.tapEnable(tap: tap, enable: on) }
    }

    private func start() {
        let mask = Self.types.reduce(CGEventMask(0)) { $0 | 1 << CGEventMask($1) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: { _, type, event, _ in
            PointerBlock.shared.handle(type, event)
        }, userInfo: nil)
        guard let tap else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    }

    private func handle(_ type: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(e)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap, Prefs.shared.blockPointer { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if e.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid()) { return pass }   // Learn's own
        // The cursor has already moved by the time the event gets here: put it back where it was.
        if type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged {
            let p = e.location
            CGWarpMouseCursorPosition(CGPoint(x: p.x - CGFloat(e.getDoubleValueField(.mouseEventDeltaX)),
                                              y: p.y - CGFloat(e.getDoubleValueField(.mouseEventDeltaY))))
        }
        return nil
    }
}
