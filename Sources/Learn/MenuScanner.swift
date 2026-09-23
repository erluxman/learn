import ApplicationServices

/// Reads every menu item (with or without a key equivalent) from an app's menu bar via the Accessibility API.
enum MenuScanner {
    private static let attrs = [
        kAXTitleAttribute, kAXChildrenAttribute, "AXMenuItemCmdChar", "AXMenuItemCmdVirtualKey",
        "AXMenuItemCmdModifiers", "AXMenuItemCmdGlyph",
    ] as CFArray

    private static let skipLists: Set<String> = ["Open Recent", "Recent Items", "History", "Bookmarks", "Recently Closed", "Services"]

    static func menuBar(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 3)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &bar) == .success else { return nil }
        return (bar as! AXUIElement)
    }

    static func children(_ el: AXUIElement) -> [AXUIElement] {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &v)
        return v as? [AXUIElement] ?? []
    }

    static func title(_ el: AXUIElement) -> String {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &v)
        return v as? String ?? ""
    }

    static func scan(pid: pid_t) -> [Shortcut] { scanWithGaps(pid: pid).items }

    /// Items plus the paths of submenus that were empty (not filled in yet by the app).
    static func scanWithGaps(pid: pid_t) -> (items: [Shortcut], empty: [[String]]) {
        guard let bar = menuBar(pid: pid) else { return ([], []) }
        var out: [Shortcut] = []
        var empty: [[String]] = []
        var seen = Set<String>()
        for top in children(bar).dropFirst() {   // first = Apple menu, same in every app (covered by System list)
            let name = title(top)
            for menu in children(top) { walk(menu, path: [name], depth: 0, into: &out, empty: &empty, seen: &seen) }
        }
        return (out, empty)
    }

    private static func walk(_ menu: AXUIElement, path: [String], depth: Int, into out: inout [Shortcut],
                             empty: inout [[String]], seen: inout Set<String>) {
        guard depth < 6 else { return }
        for item in children(menu) {
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(item, attrs, [], &raw) == .success,
                  let v = raw as? [AnyObject], v.count == 6 else { continue }
            let t = (v[0] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            let kids = v[1] as? [AXUIElement] ?? []
            if !kids.isEmpty {
                for sub in kids {
                    if children(sub).isEmpty { empty.append(path + [t]) }
                    walk(sub, path: path + [t], depth: depth + 1, into: &out, empty: &empty, seen: &seen)
                }
                continue
            }
            let char = (v[2] as? String ?? "").trimmingCharacters(in: .controlCharacters)
            let vk = (v[3] as? NSNumber)?.intValue
            let mods = Mods(ax: (v[4] as? NSNumber)?.intValue ?? 0)
            let glyph = (v[5] as? NSNumber)?.intValue ?? 0

            let key: String, code: Int?
            if let g = Keys.glyphs[glyph] {
                (key, code) = (g.0, g.1)
            } else if !char.isEmpty {
                key = char == " " ? "Space" : char.uppercased()
                code = Keys.code(for: char)?.0
            } else if let vk, vk != 0, let n = Keys.names[vk] {   // vk 0 ("A") = unset when char is empty
                (key, code) = (n, vk)
            } else {
                // No shortcut: keep as a plain menu command (still runnable via AXPress),
                // except long dynamic lists (recent files, browser history/bookmarks).
                if path.contains(where: skipLists.contains) { continue }
                (key, code) = ("", nil)
            }

            let s = Shortcut(path: path + [t], key: key, keyCode: code, mods: key.isEmpty ? [] : mods)
            if seen.insert(s.id).inserted { out.append(s) }
        }
    }

    /// Some apps (JetBrains IDEs, other Java/Electron apps) fill submenus only when they're first opened.
    /// Opens each top menu that has empty submenus, highlights its way into them, then closes the menu.
    /// The menu flashes on screen briefly. Returns true if anything was opened.
    @discardableResult
    static func expandLazySubmenus(pid: pid_t) -> Bool {
        guard let bar = menuBar(pid: pid) else { return false }
        var opened = false
        for top in children(bar).dropFirst() {
            guard let menu = children(top).first, needsExpand(menu, depth: 0) else { continue }
            AXUIElementPerformAction(top, kAXPressAction as CFString)
            usleep(250_000)
            openSubmenus(menu, depth: 0)
            AXUIElementPerformAction(menu, kAXCancelAction as CFString)
            usleep(100_000)
            opened = true
        }
        return opened
    }

    private static func needsExpand(_ menu: AXUIElement, depth: Int) -> Bool {
        guard depth < 5 else { return false }
        return children(menu).contains { item in
            children(item).contains { sub in children(sub).isEmpty || needsExpand(sub, depth: depth + 1) }
        }
    }

    private static func openSubmenus(_ menu: AXUIElement, depth: Int) {
        guard depth < 5 else { return }
        for item in children(menu) {
            guard let sub = children(item).first, children(sub).isEmpty || needsExpand(sub, depth: depth + 1) else { continue }
            AXUIElementSetAttributeValue(item, kAXSelectedAttribute as CFString, kCFBooleanTrue)
            usleep(150_000)
            openSubmenus(sub, depth: depth + 1)
        }
    }

    /// Presses a menu item. If a lazy submenu hasn't been filled yet, opens the menu path first so the app fills it.
    static func press(path: [String], pid: pid_t) -> Bool {
        if let item = find(path: path, pid: pid) {
            return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
        }
        guard let bar = menuBar(pid: pid), let first = path.first,
              let top = children(bar).first(where: { title($0) == first }) else { return false }
        AXUIElementPerformAction(top, kAXPressAction as CFString)
        usleep(200_000)
        var node = top
        for (i, name) in path.dropFirst().enumerated() {
            guard let next = children(node).flatMap({ children($0) }).first(where: { title($0) == name }) else {
                if let menu = children(top).first { AXUIElementPerformAction(menu, kAXCancelAction as CFString) }
                return false
            }
            if i < path.count - 2 {   // submenu on the way: highlight it so it opens and fills
                AXUIElementSetAttributeValue(next, kAXSelectedAttribute as CFString, kCFBooleanTrue)
                usleep(150_000)
            }
            node = next
        }
        return AXUIElementPerformAction(node, kAXPressAction as CFString) == .success
    }

    /// Finds a menu item by its title path.
    static func find(path: [String], pid: pid_t) -> AXUIElement? {
        guard let bar = menuBar(pid: pid), let first = path.first,
              let top = children(bar).first(where: { title($0) == first }) else { return nil }
        var node = top
        for name in path.dropFirst() {
            let items = children(node).flatMap { children($0) }   // item → AXMenu → items
            guard let next = items.first(where: { title($0) == name }) else { return nil }
            node = next
        }
        return node
    }
}
