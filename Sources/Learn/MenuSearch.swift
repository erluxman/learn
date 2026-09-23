import AppKit

/// Search inside an open right-click menu without closing it: typed text shows in a bubble,
/// the best match (same ranking as Learn's list) is highlighted in the real menu, ↩ runs it.
final class MenuSearch {
    private struct Item { let path: [String]; let refs: [AXUIElement] }   // refs: parent submenu items…, item

    private let overlay = Overlay()
    private var items: [Item] = []
    private var matches: [Item] = []
    private var index = 0
    private var query = ""
    private var menu: AXUIElement?
    private var watch: Timer?
    var active: Bool { menu != nil }
    var onKeysCaptured: (Bool) -> Void = { _ in }

    /// Call right after a context menu was opened for `pid` around `point` (AX coords).
    func start(pid: pid_t, near point: CGPoint) {
        stop()
        DispatchQueue.global(qos: .userInteractive).async {
            var found: AXUIElement?
            for _ in 0..<15 where found == nil {
                Thread.sleep(forTimeInterval: 0.1)
                found = Self.findOpenMenu(pid: pid, near: point)
            }
            Debug.log("menuSearch: pid=\(pid) near=\(point) found=\(found != nil)")
            guard let found else { return }
            let items = Self.collect(found, path: [], parents: [], depth: 0)
            Debug.log("menuSearch: \(items.count) items: \(items.prefix(8).map { $0.path.joined(separator: "▸") })")
            DispatchQueue.main.async {
                guard !items.isEmpty else { return }
                self.menu = found
                self.items = items
                self.matches = items
                self.render()
                self.onKeysCaptured(true)
                // Menu closed by mouse / app → leave search mode.
                self.watch = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                    guard let self, let m = self.menu else { return }
                    var role: CFTypeRef?
                    if AXUIElementCopyAttributeValue(m, kAXRoleAttribute as CFString, &role) != .success { self.stop() }
                }
            }
        }
    }

    func stop() {
        watch?.invalidate(); watch = nil
        menu = nil; items = []; matches = []; query = ""; index = 0
        overlay.hide()
        onKeysCaptured(false)
    }

    /// All keys come here while the menu is open.
    func handle(keyCode: Int, mods: Mods) -> Bool {
        switch keyCode {
        case 53:                                   // ⎋ close menu
            if let menu { AXUIElementPerformAction(menu, kAXCancelAction as CFString) }
            stop()
        case 36, 76:                               // ↩ run highlighted
            guard index < matches.count else { NSSound.beep(); return true }
            let item = matches[index]
            stop()
            DispatchQueue.global(qos: .userInteractive).async { Self.press(item) }
        case 125: move(1)                          // ↓
        case 126: move(-1)                         // ↑
        case 51: query = String(query.dropLast()); refilter()   // ⌫
        default:
            guard mods.isDisjoint(with: [.cmd, .ctrl]), let ch = keyCode == 49 ? " " : Keys.names[keyCode],
                  ch.count == 1 else { return true }
            query += ch.lowercased()
            refilter()
        }
        return true
    }

    private func move(_ d: Int) {
        guard !matches.isEmpty else { return }
        index = (index + d + matches.count) % matches.count
        highlight()
        render()
    }

    private func refilter() {
        matches = query.isEmpty ? items
            : items.compactMap { i in Fuzzy.rank(query, title: i.path.last ?? "", context: i.path.joined(separator: " ")).map { (i, $0) } }
                .sorted { ($0.1, -($0.0.path.last?.count ?? 0)) > ($1.1, -($1.0.path.last?.count ?? 0)) }.map(\.0)
        index = 0
        if matches.isEmpty { NSSound.beep() } else { highlight() }
        render()
    }

    /// Highlight in the real menu; for submenu items open the parent chain first.
    private func highlight() {
        guard index < matches.count else { return }
        let codes = matches[index].refs.map { AXUIElementSetAttributeValue($0, kAXSelectedAttribute as CFString, kCFBooleanTrue).rawValue }
        Debug.log("menuSearch: highlight '\(matches[index].path.joined(separator: "▸"))' results=\(codes)")
    }

    private func render() {
        guard let menu, let f = Self.frame(menu) else { return }
        let best = index < matches.count ? matches[index].path.joined(separator: " ▸ ") : "no match"
        let text = query.isEmpty ? "⌕ type to search \(items.count) items" : "⌕ \(query)  →  \(best)  (\(matches.count))"
        overlay.show([Overlay.Mark(frame: CGRect(x: f.minX, y: f.minY - 24, width: max(f.width, 300), height: 22),
                                   label: text, typed: 0)])
    }

    // MARK: AX

    private static func press(_ item: Item) {
        for r in item.refs.dropLast() {
            AXUIElementSetAttributeValue(r, kAXSelectedAttribute as CFString, kCFBooleanTrue)
            usleep(150_000)
        }
        if let last = item.refs.last {
            let r = AXUIElementPerformAction(last, kAXPressAction as CFString)
            Debug.log("menuSearch: press '\(item.path.joined(separator: "▸"))' result=\(r.rawValue)")
            if r != .success { DispatchQueue.main.async { NSSound.beep() } }
        }
    }

    private static func findOpenMenu(pid: pid_t, near p: CGPoint) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        for c in children(app) where role(c) == "AXMenu" { return c }
        // What sits just below-right of the click point? Context menus open there.
        var hit: AXUIElement?
        if AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x + 12), Float(p.y + 12), &hit) == .success,
           var el = hit {
            for _ in 0..<5 {
                if role(el) == "AXMenu" { return el }
                guard let parent: AXUIElement = value(el, kAXParentAttribute) else { break }
                el = parent
            }
        }
        if let f: AXUIElement = value(app, kAXFocusedUIElementAttribute), role(f) == "AXMenuItem",
           let parent: AXUIElement = value(f, kAXParentAttribute), role(parent) == "AXMenu" { return parent }
        return nil
    }

    private static func collect(_ menu: AXUIElement, path: [String], parents: [AXUIElement], depth: Int) -> [Item] {
        guard depth < 4 else { return [] }
        var out: [Item] = []
        for it in children(menu) where role(it) == "AXMenuItem" {
            let t = ((value(it, kAXTitleAttribute) as String?) ?? "").trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            let subs = children(it).filter { role($0) == "AXMenu" }
            if let sub = subs.first { out += collect(sub, path: path + [t], parents: parents + [it], depth: depth + 1) }
            else if (value(it, kAXEnabledAttribute) as Bool?) != false { out.append(Item(path: path + [t], refs: parents + [it])) }
        }
        return out
    }

    private static func children(_ e: AXUIElement) -> [AXUIElement] { value(e, kAXChildrenAttribute) ?? [] }
    private static func role(_ e: AXUIElement) -> String { value(e, kAXRoleAttribute) ?? "" }
    private static func value<T>(_ e: AXUIElement, _ k: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success else { return nil }
        return v as? T
    }
    private static func frame(_ e: AXUIElement) -> CGRect? {
        guard let p: AXValue = value(e, kAXPositionAttribute), let s: AXValue = value(e, kAXSizeAttribute) else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(p, .cgPoint, &pt); AXValueGetValue(s, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }
}
