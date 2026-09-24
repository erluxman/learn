import AppKit

/// Bottom-centre bubble showing the shortcut just pressed, recorded or run by Learn, with its command name
/// when Learn knows it. A sticky message (pointer mode) stays up and returns after each flash. Main-thread only.
final class KeyHUD {
    static let shared = KeyHUD()

    private var window: NSPanel?
    private let keys = NSTextField(labelWithString: "")
    private let caption = NSTextField(labelWithString: "")
    private var sticky: (keys: String, caption: String)?
    private var hideWork: DispatchWorkItem?
    private var generation = 0   // a fade-out only orders the window out if nothing was shown since

    /// Key tap feed: combos with ⌘/⌃/⌥ and F-keys only, so plain typing never shows up.
    func pressed(code: Int, mods: Mods, app: String?) {
        guard let name = Keys.names[code] else { return }
        let fkey = name.hasPrefix("F") && name.count > 1
        guard fkey || !mods.isDisjoint(with: [.cmd, .ctrl, .opt]) else { return }
        let display = Shortcut(path: [], key: name, keyCode: code, mods: mods).display
        flash(display, caption: Self.title(code: code, mods: mods, app: app))
    }

    func flash(_ k: String, caption c: String? = nil) {
        guard Prefs.shared.showKeyHUD, !k.isEmpty else { return }
        present(k, c ?? "")
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let s = self.sticky { self.present(s.keys, s.caption) } else { self.fadeOut() }
        }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: w)
    }

    /// Stays until cleared with nil; shown even when the shortcut display is off (it's a mode indicator).
    func setSticky(_ k: String?, caption c: String = "") {
        sticky = k.map { ($0, c) }
        hideWork?.cancel()
        if let s = sticky { present(s.keys, s.caption) } else { fadeOut() }
    }

    /// What the combo does in `app`: Learn binding first, then the app's menus, then system shortcuts.
    static func title(code: Int, mods: Mods, app: String?) -> String? {
        if Prefs.shared.panelKey.matches(code, mods) { return "Open Learn" }
        let scope = app == Bundle.main.bundleIdentifier ? "" : (app ?? "")
        if let b = Bindings.shared.match(scope, keyCode: code, mods: mods) { return b.path.last }
        func hit(_ s: Shortcut) -> Bool {
            guard s.hasKey else { return false }
            var m = s.mods.subtracting(.fn), c = s.keyCode
            if c == nil, let (k, shift) = Keys.code(for: s.key) { c = k; if shift { m.insert(.shift) } }
            return c == code && m == mods
        }
        for id in [scope, SystemShortcuts.bundleID] where !id.isEmpty {
            if let s = ShortcutStore.shared.get(id)?.shortcuts.first(where: hit) { return s.title }
        }
        return nil
    }

    // MARK: Window

    private func present(_ k: String, _ c: String) {
        let w = window ?? build()
        generation += 1
        keys.stringValue = k
        caption.stringValue = String(c.prefix(110))
        caption.isHidden = c.isEmpty
        let size = w.contentView!.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let s = screen?.visibleFrame {
            w.setFrame(NSRect(x: s.midX - size.width / 2, y: s.minY + 64, width: size.width, height: size.height), display: true)
        }
        w.alphaValue = 1
        w.orderFrontRegardless()
    }

    private func fadeOut() {
        guard let w = window, w.isVisible else { return }
        let gen = generation
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; w.animator().alphaValue = 0 }) { [weak self] in
            if self?.generation == gen { w.orderOut(nil) } else { w.alphaValue = 1 }
        }
    }

    private func build() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let fx = NSVisualEffectView()
        fx.material = .hudWindow
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.appearance = NSAppearance(named: .vibrantDark)
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 14
        fx.layer?.masksToBounds = true

        keys.font = .systemFont(ofSize: 30, weight: .semibold)
        keys.textColor = .white
        keys.alignment = .center
        caption.font = .systemFont(ofSize: 14, weight: .medium)
        caption.textColor = NSColor.white.withAlphaComponent(0.75)
        caption.alignment = .center
        let stack = NSStackView(views: [keys, caption])
        stack.orientation = .vertical
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 22, bottom: 12, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: fx.leadingAnchor), stack.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            stack.topAnchor.constraint(equalTo: fx.topAnchor), stack.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
        ])
        p.contentView = fx
        window = p
        return p
    }
}
