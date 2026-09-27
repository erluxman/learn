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
    /// `windowTitle`: only that window (used to scan Learn's own Settings window).
    /// `only`: scan just this window (Ghostty's quick terminal, grabbed before it hid).
    static func scan(pid: pid_t, budget: TimeInterval = 0.6, limit: Int = 4000, windowTitle: String? = nil,
                     only: AXUIElement? = nil) -> [ScreenElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)   // Electron
        if enableWebContent(app, pid: pid) { usleep(350_000) }   // first time: give the browser a moment to build the page's tree
        var windows: [AXUIElement] = []
        if let w: AXUIElement = value(app, kAXFocusedWindowAttribute) { windows.append(w) }
        for w in (value(app, kAXWindowsAttribute) as [AXUIElement]?) ?? [] where !windows.contains(where: { CFEqual($0, w) }) {
            if (value(w, kAXMinimizedAttribute) as Bool?) != true { windows.append(w) }
        }
        if let windowTitle { windows = windows.filter { (value($0, kAXTitleAttribute) as String?) == windowTitle } }
        if let only { windows = [only] }
        let deadline = Date().addingTimeInterval(budget)
        var out: [ScreenElement] = []
        var visited = 0
        for w in windows.prefix(4) {
            guard let wf = frame(w) else { continue }
            walk(w, clip: wf, depth: 0, inRow: false, inWeb: false, out: &out, visited: &visited, limit: limit, deadline: deadline)
        }
        Debug.log("scan pid=\(pid) windows=\(windows.count) visited=\(visited) found=\(out.count) web=\(out.filter(\.web).count) timedOut=\(Date() >= deadline)")
        return out
    }

    private static func walk(_ el: AXUIElement, clip: CGRect, depth: Int, inRow: Bool, inWeb: Bool, out: inout [ScreenElement],
                             visited: inout Int, limit: Int, deadline: Date) {
        guard depth < 80, visited < limit, Date() < deadline else { return }   // web apps nest 50+ deep
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
            if editable.contains(role) { text = fieldText(el, frame: f, label: text, hint: v[8] as? String, value: v[4] as? String) }
            else if text.isEmpty, let s = v[4] as? String { text = s }
            if text.isEmpty, role == "AXRow" || role == "AXCell" || role == "AXLink" { text = innerText(el, depth: 0) }
            let sub = v[1] as? String
            out.append(ScreenElement(ref: el, role: role, roleName: sub == "AXSearchField" ? "Search Field" : name,
                                     text: String(text.prefix(80)), frame: f.intersection(clip), web: inWeb))
            if role == "AXTextArea", let screen = v[4] as? String { out += terminalItems(el, text: screen, frame: f) }
            if role != "AXRow" && role != "AXCell" && role != "AXGroup" { return }   // leaf-like controls
        }
        for k in kids { walk(k, clip: clip, depth: depth + 1, inRow: inRow || role == "AXRow", inWeb: inWeb, out: &out, visited: &visited, limit: limit, deadline: deadline) }
    }

    /// Chromium browsers (Brave, Chrome, Edge, Arc…) only expose a page's contents to accessibility once an assistive app
    /// turns on `AXEnhancedUserInterface`, and forget it when they restart — without it only the toolbar is scannable.
    /// Returns true when it was off (just turned on). Brave reports an error on the set but applies it anyway.
    static func enableWebContent(_ app: AXUIElement, pid: pid_t) -> Bool {
        guard isChromiumBrowser(pid), (value(app, enhancedUI) as Bool?) != true else { return false }
        AXUIElementSetAttributeValue(app, enhancedUI as CFString, kCFBooleanTrue)
        Debug.log("enabled web accessibility in pid \(pid)")
        return true
    }
    /// Keeps it on in every Chromium browser: at launch, when one starts, and whenever one comes to the front — so the
    /// page is already scannable when Learn opens (turning it on takes the browser ~2 s). Never turned off.
    static func keepWebContentOn(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard isChromiumBrowser(pid) else { return }
        DispatchQueue.global(qos: .utility).async {
            let ax = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(ax, 0.5)
            _ = enableWebContent(ax, pid: pid)
        }
    }
    static func isChromiumBrowser(_ pid: pid_t) -> Bool {
        guard let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return false }
        return chromiumBrowsers.contains(where: id.hasPrefix)
    }
    static let enhancedUI = "AXEnhancedUserInterface"
    private static let chromiumBrowsers = ["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.",
                                           "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "org.chromium.Chromium", "ai.perplexity.comet"]

    /// A terminal (Ghostty…) shows TUI buttons (herdr's "new tab", "+", tab names) as plain text in one text area, and
    /// can't say where a piece of text is. But a terminal is a grid: when every line has the same length, line = row
    /// and character = column, so each piece's frame follows from where the cells sit (`TerminalGrid`). Pieces are runs
    /// of text split at 2+ spaces and box-drawing lines; long sentences (program output) are left out. They're clicked for real.
    private static func terminalItems(_ el: AXUIElement, text: String, frame f: CGRect) -> [ScreenElement] {
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 5, let cols = lines.first?.count, cols >= 20, lines.allSatisfy({ $0.count == cols }) else { return [] }
        var pid: pid_t = 0
        AXUIElementGetPid(el, &pid)
        let grid = TerminalGrid.make(frame: f, rows: lines.count, cols: cols, pid: pid)
        guard (4...40).contains(grid.cell.width), (8...80).contains(grid.cell.height) else { return [] }
        let breaks: Set<Character> = ["│", "┃", "║", "─", "━", "═", "┌", "┐", "└", "┘", "├", "┤", "┬", "┴", "┼", "╭", "╮", "╰", "╯", "|"]
        let bullets: Set<Character> = ["●", "○", "◉", "•", "⏺", "▸", "▶", "›", "»"]
        var out: [ScreenElement] = []
        for (row, line) in lines.enumerated() {
            let chars = Array(line)
            var col = 0
            while col < chars.count, out.count < 400 {
                // skip to the next piece
                while col < chars.count, chars[col] == " " || breaks.contains(chars[col]) || bullets.contains(chars[col]) { col += 1 }
                let start = col
                var gap = 0
                while col < chars.count, !breaks.contains(chars[col]) {
                    gap = chars[col] == " " ? gap + 1 : 0
                    if gap >= 2 { break }
                    col += 1
                }
                let piece = String(chars[start..<col]).trimmingCharacters(in: .whitespaces)
                guard !piece.isEmpty, piece.count <= 32, piece.split(separator: " ").count <= 4 else { continue }
                out.append(ScreenElement(ref: el, role: "AXStaticText", roleName: "Text", text: piece,
                                         frame: grid.frame(row: row, col: start, length: piece.count),
                                         web: true))   // web = a real click at its centre, never an AX press
            }
        }
        return out
    }

    /// Field name for search = what's visible: label + hint while empty (hint showing), label + typed value
    /// once filled (hint hidden → not searchable). Unlabeled fields borrow the text just before them.
    private static func fieldText(_ el: AXUIElement, frame: CGRect, label: String, hint: String?, value: String?) -> String {
        var hint = hint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let typed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var label = label
        if typed.isEmpty, hint.isEmpty { hint = overlaidText(el, frame: frame) ?? "" }   // rich editors (x.com…)
        if !typed.isEmpty, label == hint { label = "" }   // Chromium names unlabeled fields by their hint
        if label.isEmpty {
            label = (precedingText(el) ?? "").trimmingCharacters(in: CharacterSet(charactersIn: " ·→←•:-–—|"))
        }
        var parts = [label]
        if typed.isEmpty { if hint != label { parts.append(hint) } }
        else { parts.append(String(typed.prefix(40))) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Rich-text editors (Draft.js, Lexical, ProseMirror) draw their hint as separate text over the editor.
    /// Find static text near the field (≤4 ancestors up) whose top-left sits at the field's top-left.
    private static func overlaidText(_ el: AXUIElement, frame f: CGRect) -> String? {
        var node = el
        for _ in 0..<4 {
            guard let parent: AXUIElement = value(node, kAXParentAttribute) else { return nil }
            node = parent
            var queue = [parent], seen = 0
            while !queue.isEmpty, seen < 60 {
                let n = queue.removeFirst(); seen += 1
                if CFEqual(n, el) { continue }
                if (value(n, kAXRoleAttribute) as String?) == "AXStaticText", let t = value(n, kAXValueAttribute) as String?,
                   !t.trimmingCharacters(in: .whitespaces).isEmpty, let tf = frame(n),
                   abs(tf.minX - f.minX) < 24, abs(tf.minY - f.minY) < 24 { return t }
                queue += (value(n, kAXChildrenAttribute) as [AXUIElement]?) ?? []
            }
        }
        return nil
    }

    private static func precedingText(_ el: AXUIElement) -> String? {
        guard let parent: AXUIElement = value(el, kAXParentAttribute) else { return nil }
        let sibs: [AXUIElement] = value(parent, kAXChildrenAttribute) ?? []
        guard let i = sibs.firstIndex(where: { CFEqual($0, el) }) else { return nil }
        for s in sibs[..<i].reversed().prefix(3) {
            if (value(s, kAXRoleAttribute) as String?) == "AXStaticText", let t = value(s, kAXValueAttribute) as String?,
               !t.trimmingCharacters(in: .whitespaces).isEmpty { return t }
            let inner = innerText(s, depth: 2)
            if !inner.isEmpty { return inner }
        }
        return nil
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

    /// AX calls into Learn's *own* windows run in-process on the calling thread (straight into SwiftUI), so they
    /// must be on main. Calls into other apps are IPC and go off main so a slow app can't stall Learn.
    static func axQueue(_ pid: pid_t) -> DispatchQueue { pid == getpid() ? .main : .global(qos: .userInteractive) }
    static func pid(_ e: ScreenElement) -> pid_t { var p: pid_t = 0; AXUIElementGetPid(e.ref, &p); return p }

    /// Text fields get focus, rows get selected, everything else is pressed; last resort is a real click.
    /// Web content (Electron/browsers) reports AX success without reacting, so it always gets a real click.
    static func perform(_ e: ScreenElement) {
        Debug.log("perform \(e.roleName) '\(e.text.prefix(40))' web=\(e.web) frame=\(e.frame) front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
        if e.role == "AXLink", let url = linkURL(e) { return openLink(url, from: e) }
        if editable.contains(e.role) {   // fields: AX focus works in web views too; verify, else click
            axQueue(pid(e)).async {
                bringToFront(e)
                AXUIElementSetAttributeValue(e.ref, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                usleep(80_000)
                let ok = (value(e.ref, kAXFocusedAttribute) as Bool?) == true
                Debug.log("focus field '\(e.text.prefix(30))' ok=\(ok)")
                if !ok { click(at: CGPoint(x: e.frame.midX, y: e.frame.midY)) }
            }
            return
        }
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
        if pid != getpid() { DispatchQueue.main.async { onMenuOpened(pid, centre) } }   // search inside it (other apps)
        axQueue(pid).async {
            var names: CFArray?
            AXUIElementCopyActionNames(e.ref, &names)
            if e.web || !((names as? [String] ?? []).contains("AXShowMenu")
                 && AXUIElementPerformAction(e.ref, "AXShowMenu" as CFString) == .success) {
                bringToFront(e)
                click(at: centre, right: true)
            }
        }
    }

    /// Learn ▸ "Right-click the focused item": whatever has keyboard focus in the front app (selected row of a
    /// list, caret in a text area, focused button); nothing focused → right-click under the pointer. Call off main.
    static func rightClickFocused() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.5)
        guard var el: AXUIElement = value(axApp, kAXFocusedUIElementAttribute) else {
            return click(at: CGEvent(source: nil)?.location ?? .zero, right: true)
        }
        let role: String = value(el, kAXRoleAttribute) ?? ""
        if ["AXTable", "AXOutline", "AXList"].contains(role),   // list focused → its selected row
           let row = (value(el, kAXSelectedRowsAttribute) as [AXUIElement]?)?.first ?? (value(el, kAXSelectedChildrenAttribute) as [AXUIElement]?)?.first {
            el = row
        }
        guard var f = frame(el), f.width > 0, f.height > 0 else {
            return click(at: CGEvent(source: nil)?.location ?? .zero, right: true)
        }
        if editable.contains(role) || role == "AXWebArea", let caret = caretRect(el) { f = caret }   // text: at the caret
        var web = false, node = el
        for _ in 0..<60 {
            if (value(node, kAXRoleAttribute) as String?) == "AXWebArea" { web = true; break }
            guard let p: AXUIElement = value(node, kAXParentAttribute) else { break }
            node = p
        }
        let e = ScreenElement(ref: el, role: value(el, kAXRoleAttribute) ?? "", roleName: "", text: "", frame: f, web: web)
        Debug.log("rightClickFocused \(e.role) frame=\(f) web=\(web)")
        showMenu(e)
    }

    private static func caretRect(_ el: AXUIElement) -> CGRect? {
        guard let range: AXValue = value(el, kAXSelectedTextRangeAttribute) else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString, range, &out) == .success,
              let v = out, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CGRect.zero
        guard AXValueGetValue(v as! AXValue, .cgRect, &r), r.height > 0 else { return nil }
        return CGRect(x: r.minX, y: r.minY, width: max(r.width, 2), height: r.height)
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
            e?.flags = []   // keys still held (the ⌃ + ⌃ right-click chord) must not turn this into ⌃-click / ⌘-click
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
