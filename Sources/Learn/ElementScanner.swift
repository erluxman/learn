import AppKit

/// A clickable thing currently visible in an app window (button, row, tab, field, link…).
struct ScreenElement {
    let ref: AXUIElement
    let role: String
    let roleName: String   // "Button", "Row", …
    let text: String       // what it says ("" for unlabeled icons)
    let frame: CGRect      // AX global coords (top-left origin)
    var web = false        // inside an AXWebArea (Electron apps, browsers): AX press is unreliable → real click

    /// Shortcut-shaped row for Learn's list; path doubles as the locator for bindings.
    var shortcut: Shortcut { Shortcut(path: [ElementScanner.marker, roleName, text], key: "", keyCode: nil, mods: []) }
}

/// Reads visible, clickable elements from an app's windows via Accessibility, and clicks them.
enum ElementScanner {
    static let marker = "On screen"
    /// Called after a context menu was opened (pid, element centre) so Learn can search inside it.
    static var onMenuOpened: (pid_t, CGPoint) -> Void = { _, _ in }

    private static let roles: [String: String] = [
        "AXButton": "Button", "AXLink": "Link", "AXCheckBox": "Checkbox", "AXRadioButton": "Tab/Option",
        "AXMenuButton": "Menu Button", "AXPopUpButton": "Pop-up", "AXRow": "Row", "AXTextField": "Text Field",
        "AXTextArea": "Text Area", "AXComboBox": "Combo Box", "AXDisclosureTriangle": "Disclosure",
        "AXSegmentedControl": "Segments", "AXCell": "Cell", "AXIncrementor": "Stepper", "AXSlider": "Slider",
        "AXColorWell": "Color", "AXDockItem": "Dock Item",
    ]
    private static let editable: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]
    private static let attrs = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute,
        kAXChildrenAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXPlaceholderValueAttribute,
    ] as CFArray

    /// Focused window first, then other visible windows. Stops at `budget` seconds / `limit` nodes.
    static func scan(pid: pid_t, budget: TimeInterval = 0.6, limit: Int = 4000) -> [ScreenElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)   // Electron/Chromium
        var windows: [AXUIElement] = []
        if let w: AXUIElement = value(app, kAXFocusedWindowAttribute) { windows.append(w) }
        for w in (value(app, kAXWindowsAttribute) as [AXUIElement]?) ?? [] where !windows.contains(where: { CFEqual($0, w) }) {
            if (value(w, kAXMinimizedAttribute) as Bool?) != true { windows.append(w) }
        }
        let deadline = Date().addingTimeInterval(budget)
        var out: [ScreenElement] = []
        var visited = 0
        for w in windows.prefix(4) {
            guard let wf = frame(w) else { continue }
            walk(w, clip: wf, depth: 0, inRow: false, inWeb: false, out: &out, visited: &visited, limit: limit, deadline: deadline)
        }
        return out
    }

    private static func walk(_ el: AXUIElement, clip: CGRect, depth: Int, inRow: Bool, inWeb: Bool, out: inout [ScreenElement],
                             visited: inout Int, limit: Int, deadline: Date) {
        guard depth < 40, visited < limit, Date() < deadline else { return }
        visited += 1
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(el, attrs, [], &raw) == .success,
              let v = raw as? [AnyObject], v.count == 9 else { return }
        let role = v[0] as? String ?? ""
        let inWeb = inWeb || role == "AXWebArea"
        let f = rect(v[6], v[7])
        var clip = clip
        if let f, f.width > 0, f.height > 0 {   // 0×0 containers (common in Electron) don't clip
            guard f.intersects(clip) else { return }   // scrolled out of view → skip subtree
            if role == "AXScrollArea" || role == "AXWindow" { clip = clip.intersection(f) }
        }
        let kids = v[5] as? [AXUIElement] ?? []
        var name = roles[role]
        if role == "AXImage", let t = v[2] as? String, !t.isEmpty, hasPress(el) { name = "Icon" }
        if inRow && role == "AXCell" { name = nil }   // the row already covers its cells
        if let name, let f, f.width > 3, f.height > 3 {
            var text = [v[2], v[3], v[8]].compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? ""
            if text.isEmpty, !editable.contains(role), let s = v[4] as? String { text = s }
            if text.isEmpty, role == "AXRow" || role == "AXCell" || role == "AXLink" { text = innerText(el, depth: 0) }
            let sub = v[1] as? String
            out.append(ScreenElement(ref: el, role: role, roleName: sub == "AXSearchField" ? "Search Field" : name,
                                     text: String(text.prefix(80)), frame: f.intersection(clip), web: inWeb))
            if role != "AXRow" && role != "AXCell" && role != "AXGroup" { return }   // leaf-like controls
        }
        for k in kids { walk(k, clip: clip, depth: depth + 1, inRow: inRow || role == "AXRow", inWeb: inWeb, out: &out, visited: &visited, limit: limit, deadline: deadline) }
    }

    /// First bits of static text inside a row/cell/link, e.g. a file name in Finder's list.
    private static func innerText(_ el: AXUIElement, depth: Int) -> String {
        guard depth < 4 else { return "" }
        var parts: [String] = []
        for k in (value(el, kAXChildrenAttribute) as [AXUIElement]?) ?? [] {
            if (value(k, kAXRoleAttribute) as String?) == "AXStaticText", let s = value(k, kAXValueAttribute) as String?,
               !s.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(s) }
            else { let t = innerText(k, depth: depth + 1); if !t.isEmpty { parts.append(t) } }
            if parts.count >= 2 { break }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    /// Text fields get focus, rows get selected, everything else is pressed; last resort is a real click.
    /// Web content (Electron/browsers) reports AX success without reacting, so it always gets a real click.
    static func perform(_ e: ScreenElement) {
        Debug.log("perform \(e.roleName) '\(e.text.prefix(40))' web=\(e.web) frame=\(e.frame) front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
        if e.role == "AXLink", let url = linkURL(e) { return openLink(url, from: e) }
        if e.web {
            DispatchQueue.global(qos: .userInteractive).async {
                bringToFront(e)
                click(at: CGPoint(x: e.frame.midX, y: e.frame.midY))
            }
            return
        }
        var names: CFArray?
        AXUIElementCopyActionNames(e.ref, &names)
        let actions = names as? [String] ?? []
        if editable.contains(e.role),
           AXUIElementSetAttributeValue(e.ref, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success { return }
        if actions.contains(kAXPressAction), AXUIElementPerformAction(e.ref, kAXPressAction as CFString) == .success { return }
        if e.role == "AXRow" || e.role == "AXCell",
           AXUIElementSetAttributeValue(e.ref, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success { return }
        click(at: CGPoint(x: e.frame.midX, y: e.frame.midY))
    }

    /// Opens the element's context menu: its own AXShowMenu action, else a real right-click at its centre.
    /// Off the main thread: AXShowMenu can block until the menu closes, which would stall Learn's key tap.
    static func showMenu(_ e: ScreenElement) {
        var pid: pid_t = 0
        AXUIElementGetPid(e.ref, &pid)
        let centre = CGPoint(x: e.frame.midX, y: e.frame.midY)
        DispatchQueue.main.async { onMenuOpened(pid, centre) }   // starts looking for the menu (polls ~1.5s)
        DispatchQueue.global(qos: .userInteractive).async {
            var names: CFArray?
            AXUIElementCopyActionNames(e.ref, &names)
            if e.web || !((names as? [String] ?? []).contains("AXShowMenu")
                 && AXUIElementPerformAction(e.ref, "AXShowMenu" as CFString) == .success) {
                bringToFront(e)
                click(at: centre, right: true)
            }
        }
    }

    /// For bindings: find by role + text in the frontmost app now, then perform.
    static func pressMatching(path: [String], pid: pid_t) -> Bool {
        guard path.count == 3 else { return false }
        guard let e = scan(pid: pid, budget: 0.8).first(where: { $0.roleName == path[1] && $0.text == path[2] }) else { return false }
        DispatchQueue.main.async { perform(e) }
        return true
    }

    /// Real mouse click, then put the pointer back where it was. Shaped like a hardware click (move → down → up,
    /// click count 1) because Chromium/Electron ignore synthetic clicks without a click count.
    static func click(at p: CGPoint, right: Bool = false) {
        let back = CGEvent(source: nil)?.location
        let src = CGEventSource(stateID: .hidSystemState)
        let button: CGMouseButton = right ? .right : .left
        let (down, up): (CGEventType, CGEventType) = right ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
        func post(_ type: CGEventType) {
            let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: button)
            e?.setIntegerValueField(.mouseEventClickState, value: 1)
            e?.post(tap: .cghidEventTap)
        }
        Debug.log("click \(right ? "right" : "left") at \(p) front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
        post(.mouseMoved)
        usleep(30_000)
        post(down)
        usleep(40_000)
        post(up)
        if let back, !right {   // keep the pointer on a context menu so it isn't dismissed by the move
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { CGWarpMouseCursorPosition(back) }
        }
    }

    static func linkURL(_ e: ScreenElement) -> URL? {
        guard let url: URL = value(e.ref, "AXURL"), let scheme = url.scheme, ["http", "https", "file", "mailto"].contains(scheme)
        else { return nil }
        return url
    }

    /// Opens a link's address in a new tab of the browser that shows it; non-browsers (Slack…) use the default browser.
    static func openLink(_ url: URL, from e: ScreenElement) {
        var pid: pid_t = 0
        AXUIElementGetPid(e.ref, &pid)
        Debug.log("openLink \(url.absoluteString.prefix(80))")
        let owner = NSRunningApplication(processIdentifier: pid)?.bundleURL
        let browsers = NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)
        if let owner, browsers.contains(where: { $0.standardizedFileURL == owner.standardizedFileURL }) {
            NSWorkspace.shared.open([url], withApplicationAt: owner, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// Real clicks only reach the page if the app is already active: Chromium/Electron spend the first
    /// click on an inactive window just activating it. Activate and wait (≤1s). Call off the main thread.
    static func bringToFront(_ e: ScreenElement) {
        var pid: pid_t = 0
        AXUIElementGetPid(e.ref, &pid)
        func front() -> Bool { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
        guard !front(), let app = NSRunningApplication(processIdentifier: pid) else { Debug.log("bringToFront: already front"); return }
        DispatchQueue.main.async { app.activate() }
        for _ in 0..<20 where !front() { usleep(50_000) }
        usleep(120_000)   // let the window become key
        Debug.log("bringToFront: front=\(front())")
    }

    // MARK: AX helpers

    private static func hasPress(_ el: AXUIElement) -> Bool {
        var names: CFArray?
        AXUIElementCopyActionNames(el, &names)
        return (names as? [String])?.contains(kAXPressAction) == true
    }

    private static func value<T>(_ el: AXUIElement, _ attr: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? T
    }

    private static func frame(_ el: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &p)
        AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &s)
        return rect(p, s)
    }

    private static func rect(_ p: AnyObject?, _ s: AnyObject?) -> CGRect? {
        guard let p, let s, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &pt), AXValueGetValue(s as! AXValue, .cgSize, &sz) else { return nil }
        return CGRect(origin: pt, size: sz)
    }
}
