import AppKit

/// Moves the frontmost app's focused window to another display (any: built-in, external, Sidecar iPad),
/// keeping its relative spot and shrinking it to fit. The pointer follows the window.
enum WindowMover {
    static let prefix = "Move window to "

    struct Screen { let name: String; let bounds: CGRect; let visible: CGRect }   // CG coords (top-left origin)

    /// Displays left to right, like pointer mode's next-screen order; duplicate names get " 2", " 3"…
    static func screens() -> [Screen] {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        var seen: [String: Int] = [:]
        return NSScreen.screens.compactMap { s -> (NSScreen, CGRect)? in
            guard let id = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            return (s, CGDisplayBounds(id))
        }
        .sorted { ($0.1.minX, $0.1.minY) < ($1.1.minX, $1.1.minY) }
        .map { s, bounds in
            let v = s.visibleFrame
            let base = s.localizedName.hasPrefix("Sidecar") ? "iPad (Sidecar)" : s.localizedName   // so "move to ipad" finds it
            seen[base, default: 0] += 1
            let n = seen[base]!
            return Screen(name: n > 1 ? "\(base) \(n)" : base, bounds: bounds,
                          visible: CGRect(x: v.minX, y: primaryH - v.maxY, width: v.width, height: v.height))
        }
    }

    /// One searchable "Move window to <display>" command per connected display.
    static var paths: [[String]] { screens().map { [LearnActions.group, prefix + $0.name] } }

    /// `name` nil = next display (wrapping).
    static func move(to name: String?) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return NSSound.beep() }
        let pid = app.processIdentifier, list = screens()
        ElementScanner.axQueue(pid).async {
            let ax = AXUIElementCreateApplication(pid)
            guard list.count > 1, let win = element(ax, kAXFocusedWindowAttribute) ?? element(ax, kAXMainWindowAttribute),
                  let f = frame(win) else { return DispatchQueue.main.async { NSSound.beep() } }
            var full: CFTypeRef?
            if AXUIElementCopyAttributeValue(win, "AXFullScreen" as CFString, &full) == .success, full as? Bool == true {
                return DispatchQueue.main.async { NSSound.beep() }   // full-screen windows own their Space; can't move
            }
            let i = list.firstIndex { $0.bounds.contains(CGPoint(x: f.midX, y: f.midY)) }
                ?? list.indices.max { area(list[$0].bounds, f) < area(list[$1].bounds, f) } ?? 0
            guard let dest = name.map({ n in list.first { $0.name == n } }) ?? list[(i + 1) % list.count],
                  dest.name != list[i].name else { return DispatchQueue.main.async { NSSound.beep() } }
            let from = list[i].visible, to = dest.visible
            let w = min(f.width, to.width), h = min(f.height, to.height)
            // Same share of free space on both screens: a window hugging the right edge stays on the right.
            func share(_ pos: CGFloat, _ lo: CGFloat, _ free: CGFloat) -> CGFloat { free > 0 ? min(max((pos - lo) / free, 0), 1) : 0 }
            let x = to.minX + (to.width - w) * share(f.minX, from.minX, from.width - f.width)
            let y = to.minY + (to.height - h) * share(f.minY, from.minY, from.height - f.height)
            // Position first (a size too big for the old screen gets clamped), then size, then position again.
            set(win, kAXPositionAttribute, CGPoint(x: x, y: y))
            set(win, kAXSizeAttribute, CGSize(width: w, height: h))
            set(win, kAXPositionAttribute, CGPoint(x: x, y: y))
            let landed = frame(win) ?? CGRect(x: x, y: y, width: w, height: h)
            DispatchQueue.main.async {
                CGWarpMouseCursorPosition(CGPoint(x: landed.midX, y: landed.midY))
                CGAssociateMouseAndMouseCursorPosition(1)
            }
        }
    }

    private static func area(_ a: CGRect, _ b: CGRect) -> CGFloat { let r = a.intersection(b); return r.isNull ? 0 : r.width * r.height }

    private static func element(_ e: AXUIElement, _ attr: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success, let v,
              CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private static func frame(_ w: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &s) == .success else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pt)
        AXValueGetValue(s as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }

    private static func set(_ w: AXUIElement, _ attr: String, _ point: CGPoint) {
        var v = point
        if let ax = AXValueCreate(.cgPoint, &v) { AXUIElementSetAttributeValue(w, attr as CFString, ax) }
    }

    private static func set(_ w: AXUIElement, _ attr: String, _ size: CGSize) {
        var v = size
        if let ax = AXValueCreate(.cgSize, &v) { AXUIElementSetAttributeValue(w, attr as CFString, ax) }
    }
}
