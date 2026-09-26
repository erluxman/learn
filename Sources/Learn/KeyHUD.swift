import AppKit

/// Look of the shortcut bubble. Edited in Settings ▸ On Screen (HUDStyleSections).
struct HUDStyle: Codable, Hashable {
    enum Position: String, Codable, CaseIterable {
        case topLeft, topCenter, topRight, middleLeft, center, middleRight, bottomLeft, bottomCenter, bottomRight
    }
    enum Motion: String, Codable, CaseIterable { case fade, slide, pop, none }
    /// What the box is made of. `tinted` = Liquid Glass colored by `background`; `frosted` = blur + `background` on top.
    enum Backdrop: String, Codable, CaseIterable { case solid, glass, tinted, frosted }
    struct RGBA: Codable, Hashable {
        var r, g, b, a: Double
        init(_ c: NSColor) {
            let s = c.usingColorSpace(.sRGB) ?? .white
            (r, g, b, a) = (s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent)
        }
        var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    }

    var position = Position.bottomCenter
    var margin = 64.0                 // distance from the screen edge
    var font = ""                     // "" system · ".rounded" · ".mono" · a font family name
    var bold = true
    var keySize = 30.0
    var captionSize = 14.0
    var showCaption = true            // the command name under the keys
    var textColor = RGBA(.white)
    var background = RGBA(NSColor(white: 0.1, alpha: 0.55))
    var frosted = true                // before `backdrop` existed: blur what's behind, tinted by `background`
    var backdrop: Backdrop? = .tinted // nil in styles saved before it existed → derived from `frosted`
    var cornerRadius = 14.0
    var paddingH = 22.0
    var paddingV = 10.0
    var shadow = true
    var duration = 1.4                // seconds on screen
    var motion = Motion.fade
    var animationSpeed = 0.25         // seconds

    var box: Backdrop {
        get { backdrop ?? (frosted ? .frosted : .solid) }
        set { backdrop = newValue }
    }

    func keyFont() -> NSFont { Self.font(font, size: keySize, bold: bold) }
    func captionFont() -> NSFont { Self.font(font, size: captionSize, bold: false) }

    private static func font(_ name: String, size: Double, bold: Bool) -> NSFont {
        let w: NSFont.Weight = bold ? .semibold : .medium
        switch name {
        case "": return .systemFont(ofSize: size, weight: w)
        case ".mono": return .monospacedSystemFont(ofSize: size, weight: w)
        case ".rounded":
            let f = NSFont.systemFont(ofSize: size, weight: w)
            return f.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? f
        default:
            return NSFontManager.shared.font(withFamily: name, traits: bold ? .boldFontMask : [], weight: bold ? 9 : 5, size: size)
                ?? .systemFont(ofSize: size, weight: w)
        }
    }
}

/// Bubble showing the shortcut just pressed, recorded or run by Learn, with its command name when Learn knows it.
/// A sticky message (pointer mode) stays up and returns after each flash. Main-thread only.
final class KeyHUD {
    static let shared = KeyHUD()

    private var window: NSPanel?
    private var built: HUDStyle?   // style the window was built with; rebuilt when it changes
    private var sizer: NSView?     // padded text; the window is sized to fit it
    private let keys = NSTextField(labelWithString: "")
    private let caption = NSTextField(labelWithString: "")
    private var sticky: (keys: String, caption: String)?
    private var hideWork: DispatchWorkItem?
    private var shown = false
    private var generation = 0   // an exit animation only orders the window out if nothing was shown since

    private var style: HUDStyle { Prefs.shared.hudStyle }

    /// Key tap feed: combos with ⌘/⌃/⌥ and F-keys only, so plain typing never shows up.
    func pressed(code: Int, mods: Mods, app: String?) {
        guard let name = Keys.names[code] else { return }
        let fkey = name.hasPrefix("F") && name.count > 1
        guard fkey || !mods.isDisjoint(with: [.cmd, .ctrl, .opt]) else { return }
        let display = Shortcut(path: [], key: name, keyCode: code, mods: mods).display
        flash(display, caption: Self.title(code: code, mods: mods, app: app))
    }

    /// `force`: show even when the display is turned off (the Customize window's preview).
    func flash(_ k: String, caption c: String? = nil, force: Bool = false) {
        guard force || Prefs.shared.showKeyHUD, !k.isEmpty else { return }
        present(k, c ?? "")
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let s = self.sticky { self.present(s.keys, s.caption) } else { self.hide() }
        }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + style.duration, execute: w)
    }

    /// Stays until cleared with nil; shown even when the shortcut display is off (it's a mode indicator).
    func setSticky(_ k: String?, caption c: String = "") {
        sticky = k.map { ($0, c) }
        hideWork?.cancel()
        if let s = sticky { present(s.keys, s.caption) } else { hide() }
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
        let st = style
        if built != st { build(st) }
        guard let w = window else { return }
        w.contentView?.layer?.removeAnimation(forKey: "pop")
        generation += 1
        keys.stringValue = k
        caption.stringValue = String(c.prefix(110))
        caption.isHidden = c.isEmpty || !st.showCaption
        let target = frame(for: (sizer ?? w.contentView!).fittingSize, st)
        let entering = !shown
        shown = true
        guard entering, st.motion != .none else {
            NSAnimationContext.runAnimationGroup { ctx in   // supersedes any running exit animation
                ctx.duration = 0.01
                w.animator().setFrame(target, display: true)
                w.animator().alphaValue = 1
            }
            w.orderFrontRegardless()
            return
        }
        w.alphaValue = 0
        w.setFrame(st.motion == .slide ? target.offsetBy(dx: slide(st).dx, dy: slide(st).dy) : target, display: true)
        w.orderFrontRegardless()
        if st.motion == .pop { pop(w, from: 0.85, to: 1, st) }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = st.animationSpeed
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            w.animator().setFrame(target, display: true)
            w.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard let w = window, shown else { return }
        shown = false
        let st = style, gen = generation
        guard st.motion != .none else { w.orderOut(nil); return }
        if st.motion == .pop { pop(w, from: 1, to: 0.85, st) }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = st.animationSpeed
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            if st.motion == .slide { w.animator().setFrame(w.frame.offsetBy(dx: slide(st).dx, dy: slide(st).dy), display: true) }
            w.animator().alphaValue = 0
        }) { [weak self] in
            if self?.generation == gen { w.orderOut(nil) }
        }
    }

    /// Slide in from / out toward the nearest screen edge.
    private func slide(_ st: HUDStyle) -> CGVector {
        switch st.position {
        case .topLeft, .topCenter, .topRight: CGVector(dx: 0, dy: 24)
        case .middleLeft: CGVector(dx: -24, dy: 0)
        case .middleRight: CGVector(dx: 24, dy: 0)
        default: CGVector(dx: 0, dy: -24)
        }
    }

    /// Scale about the centre (view layers anchor at the corner, so translate to compensate).
    private func pop(_ w: NSWindow, from: CGFloat, to: CGFloat, _ st: HUDStyle) {
        guard let layer = w.contentView?.layer else { return }
        let b = layer.bounds
        func t(_ s: CGFloat) -> CATransform3D {
            CATransform3DScale(CATransform3DMakeTranslation(b.width * (1 - s) / 2, b.height * (1 - s) / 2, 0), s, s, 1)
        }
        let a: CABasicAnimation
        if to == 1 {   // spring in, with a touch of overshoot
            let spring = CASpringAnimation(perceptualDuration: max(st.animationSpeed * 1.6, 0.2), bounce: 0.3)
            spring.duration = spring.settlingDuration
            a = spring
        } else {
            a = CABasicAnimation(keyPath: "transform")
            a.duration = st.animationSpeed
            a.timingFunction = CAMediaTimingFunction(name: .easeIn)
        }
        a.keyPath = "transform"
        a.fromValue = t(from)
        a.toValue = t(to)
        a.isRemovedOnCompletion = to == 1   // shrunk on exit: stay shrunk until the next show
        a.fillMode = .forwards
        layer.add(a, forKey: "pop")
    }

    private func frame(for size: CGSize, _ st: HUDStyle) -> NSRect {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let s = screen?.visibleFrame ?? .zero, m = st.margin
        let x: CGFloat, y: CGFloat
        switch st.position {
        case .topLeft, .middleLeft, .bottomLeft: x = s.minX + m
        case .topRight, .middleRight, .bottomRight: x = s.maxX - m - size.width
        default: x = s.midX - size.width / 2
        }
        switch st.position {
        case .topLeft, .topCenter, .topRight: y = s.maxY - m - size.height
        case .bottomLeft, .bottomCenter, .bottomRight: y = s.minY + m
        default: y = s.midY - size.height / 2
        }
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func build(_ st: HUDStyle) {
        let p = window ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
            p.isOpaque = false
            p.backgroundColor = .clear
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window = p
            return p
        }()
        p.hasShadow = st.shadow

        keys.font = st.keyFont()
        keys.textColor = st.textColor.ns
        keys.alignment = .center
        caption.font = st.captionFont()
        caption.textColor = st.textColor.ns.withAlphaComponent(st.textColor.a * 0.75)
        caption.alignment = .center
        keys.removeFromSuperview(); caption.removeFromSuperview()
        let stack = NSStackView(views: [keys, caption])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        // Padding as explicit constraints, so every backdrop (glass included) keeps it.
        let content = NSView()
        pin(stack, in: content, NSEdgeInsets(top: st.paddingV, left: st.paddingH, bottom: st.paddingV + 2, right: st.paddingH))

        let dark = st.textColor.ns.brightnessComponentSafe > 0.5
        var root: NSView
        switch st.box {
        case .glass, .tinted:
            if #available(macOS 26, *) {
                let glass = NSGlassEffectView()
                glass.style = st.box == .glass ? .clear : .regular
                glass.cornerRadius = st.cornerRadius
                if st.box == .tinted { glass.tintColor = st.background.ns }   // the glass itself is colored; its opacity = how strongly
                glass.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                glass.contentView = content
                root = glass
                break
            }
            fallthrough   // no Liquid Glass before macOS 26: blur instead
        case .frosted, .solid:
            let box = NSView()
            box.wantsLayer = true
            box.layer?.cornerRadius = st.cornerRadius
            box.layer?.cornerCurve = .continuous
            box.layer?.masksToBounds = true
            if st.box != .solid {
                let fx = NSVisualEffectView()
                fx.material = .hudWindow
                fx.blendingMode = .behindWindow
                fx.state = .active
                fx.appearance = NSAppearance(named: dark ? .vibrantDark : .vibrantLight)
                pin(fx, in: box)
            }
            let tint = NSView()
            tint.wantsLayer = true
            tint.layer?.backgroundColor = (st.box == .glass ? st.background.ns.withAlphaComponent(0.25) : st.background.ns).cgColor
            pin(tint, in: box)
            pin(content, in: box)
            root = box
        }
        root.wantsLayer = true
        sizer = content
        p.contentView = root
        built = st
    }

    private func pin(_ v: NSView, in parent: NSView, _ inset: NSEdgeInsets = NSEdgeInsets()) {
        v.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset.left),
            v.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset.right),
            v.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset.top),
            v.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset.bottom),
        ])
    }
}

private extension NSColor {
    var brightnessComponentSafe: CGFloat { (usingColorSpace(.sRGB) ?? .white).brightnessComponent }
}
