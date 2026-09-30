import AppKit
import SwiftUI

/// Look of the shortcut bubble. Edited in Settings ▸ On Screen (HUDStyleSections).
struct HUDStyle: Codable, Hashable {
    enum Position: String, Codable, CaseIterable {
        case topLeft, topCenter, topRight, middleLeft, center, middleRight, bottomLeft, bottomCenter, bottomRight
    }
    enum Motion: String, Codable, CaseIterable { case jelly, fade, slide, pop, none }
    /// What the box is made of. `spotlight` = Spotlight's plain dark Liquid Glass; `tinted` = Liquid Glass colored by
    /// `background`; `frosted` = blur + `background` on top.
    enum Backdrop: String, Codable, CaseIterable { case spotlight, solid, glass, tinted, frosted }
    struct RGBA: Codable, Hashable {
        var r, g, b, a: Double
        init(_ c: NSColor) {
            let s = c.usingColorSpace(.sRGB) ?? .white
            (r, g, b, a) = (s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent)
        }
        var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    }

    // Settings (Settings ▸ On Screen): where, font, animation, and the background as in Appearance.
    var position = Position.bottomCenter
    var font = ""                     // "" system · ".rounded" · ".mono" · a font family name
    var motion = Motion.jelly
    var tint = RGBA(NSColor.systemPurple)   // Liquid glass takes it at `tintStrength`; 0 = Spotlight's plain dark glass
    var tintStrength = 0.0
    var gradient = false                    // the color as a diagonal gradient of two neighbouring shades, not flat
    var cornerRadius = 26.0           // as set; drawn as `corner`

    // Settled looks, no longer settings (older saved values for them are ignored):
    var margin: Double { 64 }         // distance from the screen edge
    var bold: Bool { false }          // Spotlight's text is regular weight
    var keySize: Double { 26 }        // Spotlight's search text
    var captionSize: Double { 15 }    // Spotlight's subtitles
    var showCaption: Bool { false }   // keys only; the command name is no longer shown (or a setting)
    var textColor: RGBA { RGBA(.white) }
    var background: RGBA { RGBA(NSColor(white: 0.1, alpha: 0.55)) }
    var paddingH: Double { 24 }
    var paddingV: Double { 12 }
    var shadow: Bool { true }
    var duration: Double { 1.4 }      // seconds on screen
    var animationSpeed: Double { 0.25 }   // seconds

    /// Liquid glass is Spotlight's dark glass; older saved backdrops and their looks are ignored.
    var box: Backdrop { .spotlight }
    /// Liquid glass tinted with the chosen color at the chosen intensity; nil = plain (and on the gradient).
    var glassTint: NSColor? {
        guard tintStrength > 0 else { return nil }
        return tint.ns.withAlphaComponent(tintStrength)
    }
    /// The color washed inside the glass: flat, or a lighter hue sliding into a deeper one.
    var washColors: [NSColor] {
        let c = tint.ns.usingColorSpace(.sRGB) ?? .systemPurple
        guard gradient else { return [c, c] }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        func tone(_ dh: CGFloat, _ db: CGFloat) -> NSColor {
            NSColor(hue: (h + dh + 1).truncatingRemainder(dividingBy: 1), saturation: s, brightness: min(1, b * db), alpha: 1)
        }
        return [tone(-0.08, 1.15), tone(0.08, 0.7)]
    }

    /// One backdrop's own settings. Each backdrop starts from its defaults and remembers your changes until reset.
    struct BoxLook: Codable, Hashable {
        var color: RGBA
        var opacity: Double       // solid: fill · colored glass: intensity · blurred: tint over the blur
        var blur = 1.0            // blurred: how much blur shows
        var material = BlurStyle.hud
        var darken = 0.0          // clear glass: smoke it
        var shine = 0.35          // bright rim
    }
    var boxLooks: [String: BoxLook]? = nil
    static let maxBlurRadius = BlurStyle.maxRadius

    func defaultLook(_ b: Backdrop) -> BoxLook {
        switch b {
        case .spotlight: BoxLook(color: RGBA(.black), opacity: 0, shine: 0.2)
        case .solid: BoxLook(color: RGBA(background.ns.withAlphaComponent(1)), opacity: max(background.a, 0.85), shine: 0.15)
        case .glass: BoxLook(color: RGBA(.white), opacity: 0, darken: 0.1, shine: 0.45)
        case .tinted: BoxLook(color: RGBA(background.ns.withAlphaComponent(1)), opacity: 0.55, shine: 0.4)
        case .frosted: BoxLook(color: RGBA(background.ns.withAlphaComponent(1)), opacity: 0.2, blur: 1, material: .hud, shine: 0.25)
        }
    }
    func look(_ b: Backdrop) -> BoxLook { boxLooks?[b.rawValue] ?? defaultLook(b) }
    mutating func setLook(_ l: BoxLook, for b: Backdrop) { boxLooks = (boxLooks ?? [:]).merging([b.rawValue: l]) { $1 } }
    mutating func resetLook(_ b: Backdrop) { boxLooks?[b.rawValue] = nil }
    var current: BoxLook { defaultLook(.spotlight) }

    /// Half the bubble's height: rounder than that and the ends pinch instead of making a capsule.
    var maxCorner: Double { (NSLayoutManager().defaultLineHeight(for: keyFont()) + paddingV * 2 + 2) / 2 }
    var corner: Double { min(cornerRadius, maxCorner) }

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
    private var bubble: NSView?    // the visible box, inset by `pad` inside the window so it can stretch past its size
    private var touch: JellyTouchView?
    private var hovering = false   // pointer on the bubble: it stays up until the pointer leaves
    private static let pad: CGFloat = 20
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
        flash(display.spacedKeys, caption: Self.title(code: code, mods: mods, app: app))
    }

    /// `force`: show even when the display is turned off (the Customize window's preview).
    func flash(_ k: String, caption c: String? = nil, force: Bool = false) {
        guard force || Prefs.shared.showKeyHUD, !k.isEmpty else { return }
        present(k, c ?? "")
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, !self.hovering else { return }
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
        func hit(_ s: Shortcut) -> Bool { s.matches(code: code, mods: mods) }
        for id in [scope, SystemShortcuts.bundleID] where !id.isEmpty {
            if let s = ShortcutStore.shared.get(id)?.shortcuts.first(where: hit) { return s.title }
        }
        return nil
    }

    // MARK: Jelly

    /// Squash-and-stretch keyframes as (x scale, y scale, time 0…1). Volume roughly holds: wider means shorter.
    private enum Jelly {
        static let enter: [(CGFloat, CGFloat, Double)] = [(0.35, 0.35, 0), (1.16, 0.84, 0.3), (0.9, 1.1, 0.5), (1.05, 0.96, 0.68), (0.98, 1.02, 0.85), (1, 1, 1)]
        static let exit: [(CGFloat, CGFloat, Double)] = [(1, 1, 0), (1.12, 0.88, 0.28), (0.9, 1.08, 0.55), (0.25, 0.25, 1)]
        static let boing: [(CGFloat, CGFloat, Double)] = [(1, 1, 0), (1.08, 0.92, 0.25), (0.95, 1.05, 0.5), (1.02, 0.98, 0.75), (1, 1, 1)]
    }
    private static let hoverScale: CGFloat = 1.06

    /// Scales the bubble about its centre (view layers anchor at a corner, so each frame translates to compensate).
    private func scaled(_ sx: CGFloat, _ sy: CGFloat) -> CATransform3D {
        let b = bubble?.layer?.bounds ?? .zero
        return CATransform3DScale(CATransform3DMakeTranslation(b.width * (1 - sx) / 2, b.height * (1 - sy) / 2, 0), sx, sy, 1)
    }

    /// Runs squash-and-stretch keyframes; `keep` leaves the last frame applied (exit, press, hover) instead of snapping back.
    private func jelly(_ frames: [(CGFloat, CGFloat, Double)], duration: Double, keep: Bool = false) {
        guard let layer = bubble?.layer else { return }
        let a = CAKeyframeAnimation(keyPath: "transform")
        a.values = frames.map { scaled($0.0, $0.1) }
        a.keyTimes = frames.map { NSNumber(value: $0.2) }
        a.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: frames.count - 1)
        a.duration = duration
        a.isRemovedOnCompletion = !keep
        a.fillMode = .forwards
        layer.removeAnimation(forKey: "pop")
        layer.add(a, forKey: "pop")
    }

    /// The bubble's current (on-screen) x/y scale, so touches start from wherever it is mid-wobble.
    private var liveScale: (CGFloat, CGFloat) {
        guard let t = bubble?.layer?.presentation()?.transform else { return (1, 1) }
        return (t.m11, t.m22)
    }

    private func hover(_ on: Bool) {
        guard shown else { return }
        hovering = on
        let (x, y) = liveScale, s = on ? Self.hoverScale : 1
        jelly([(x, y, 0), (s * 1.03, s * 0.97, 0.45), (s * 0.99, s * 1.01, 0.75), (s, s, 1)], duration: 0.4, keep: true)
        if !on {   // pointer left: leave after a short beat
            hideWork?.cancel()
            let w = DispatchWorkItem { [weak self] in
                guard let self, !self.hovering else { return }
                if let s = self.sticky { self.present(s.keys, s.caption) } else { self.hide() }
            }
            hideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: w)
        }
    }

    /// Press squashes it flat like a drop of liquid under a finger; release springs it back with a wobble.
    private func press(_ down: Bool) {
        guard shown else { return }
        let (x, y) = liveScale, s = hovering ? Self.hoverScale : 1
        if down {
            jelly([(x, y, 0), (1.12, 0.86, 1)], duration: 0.1, keep: true)
        } else {
            jelly([(x, y, 0), (s * 0.92, s * 1.1, 0.22), (s * 1.06, s * 0.95, 0.45), (s * 0.98, s * 1.02, 0.7), (s, s, 1)], duration: 0.55, keep: true)
        }
    }

    // MARK: Window

    private func present(_ k: String, _ c: String) {
        let st = style
        if built != st { build(st) }
        guard let w = window else { return }
        bubble?.layer?.removeAnimation(forKey: "pop")
        generation += 1
        keys.stringValue = k
        caption.stringValue = String(c.prefix(110))
        caption.isHidden = c.isEmpty || !st.showCaption
        let target = frame(for: (sizer ?? w.contentView!).fittingSize, st).insetBy(dx: -Self.pad, dy: -Self.pad)
        let entering = !shown
        shown = true
        if !entering, st.motion == .jelly { DispatchQueue.main.async { self.jelly(Jelly.boing, duration: 0.42) } }   // after the resize lands
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
        if st.motion == .jelly {
            jelly(Jelly.enter, duration: max(st.animationSpeed * 2.6, 0.55))
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = min(st.animationSpeed, 0.15)
                w.animator().alphaValue = 1
            }
            return
        }
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
        let exit = st.motion == .jelly ? max(st.animationSpeed * 1.6, 0.36) : st.animationSpeed
        if st.motion == .jelly { jelly(Jelly.exit, duration: exit, keep: true) }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = exit
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.6, 0, 1, 1)   // holds while it squashes, then goes
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
        guard let layer = bubble?.layer else { return }
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
            p.ignoresMouseEvents = false   // hover swells it, a press squashes it; the clear margin still clicks through
            p.acceptsMouseMovedEvents = true
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
        let look = st.current
        var root: NSView
        switch st.box {
        case .spotlight, .glass, .tinted:
            if #available(macOS 26, *) {
                let glass = NSGlassEffectView()
                glass.style = st.box == .glass ? .clear : .regular
                glass.cornerRadius = st.corner
                glass.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                content.wantsLayer = true
                content.layer?.cornerRadius = st.corner
                content.layer?.cornerCurve = .continuous
                if let tint = st.glassTint {   // the glass's own tint is faint, so the color also washes the inside
                    glass.tintColor = tint
                    content.layer?.masksToBounds = true
                    pin(GradientView(st.washColors, opacity: st.tintStrength * 0.7), in: content, below: true)
                } else if st.box != .tinted {
                    if look.darken > 0 { glass.tintColor = NSColor.black.withAlphaComponent(look.darken) }
                } else {   // the glass's own tint is faint, so the color also washes the inside of the glass
                    glass.tintColor = look.color.ns.withAlphaComponent(look.opacity)
                    content.layer?.backgroundColor = look.color.ns.withAlphaComponent(look.opacity * 0.7).cgColor
                }
                shine(content.layer, look.shine)
                glass.contentView = content
                root = glass
                break
            }
            fallthrough   // no Liquid Glass before macOS 26: blur instead
        case .frosted, .solid:
            let box = NSView()
            box.wantsLayer = true
            box.layer?.cornerRadius = st.corner
            box.layer?.cornerCurve = .continuous
            box.layer?.masksToBounds = true
            if st.box == .frosted, look.material.isTunable {
                pin(BackdropBlurView(look.backdropParams(corner: st.corner)), in: box)
            } else if st.box != .solid {
                let fx = NSVisualEffectView()
                fx.material = look.material.appKitMaterial ?? .hudWindow
                fx.blendingMode = .behindWindow
                fx.state = .active
                fx.alphaValue = st.box == .frosted ? look.blur : 1
                fx.appearance = NSAppearance(named: dark ? .vibrantDark : .vibrantLight)
                pin(fx, in: box)
            }
            pin(st.glassTint == nil ? GradientView([look.color.ns, look.color.ns], opacity: look.opacity)
                                    : GradientView(st.washColors, opacity: st.tintStrength), in: box)
            pin(content, in: box)
            shine(box.layer, look.shine)
            root = box
        }
        root.wantsLayer = true
        sizer = content
        bubble = root
        let touch = JellyTouchView()
        touch.onHover = { [weak self] in self?.hover($0) }
        touch.onPress = { [weak self] in self?.press($0) }
        pin(root, in: touch, NSEdgeInsets(top: Self.pad, left: Self.pad, bottom: Self.pad, right: Self.pad))
        touch.target = root
        self.touch = touch
        hovering = false
        p.contentView = touch
        built = st
    }

    /// Bright rim around the bubble.
    private func shine(_ layer: CALayer?, _ amount: Double) {
        guard let layer, amount > 0 else { return }
        layer.borderWidth = 1
        layer.borderColor = NSColor.white.withAlphaComponent(amount * 0.7).cgColor
    }

    /// `below`: behind the views already in `parent`.
    private func pin(_ v: NSView, in parent: NSView, _ inset: NSEdgeInsets = NSEdgeInsets(), below: Bool = false) {
        v.translatesAutoresizingMaskIntoConstraints = false
        if below { parent.addSubview(v, positioned: .below, relativeTo: nil) } else { parent.addSubview(v) }
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset.left),
            v.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset.right),
            v.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset.top),
            v.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset.bottom),
        ])
    }
}

extension HUDStyle.BoxLook {
    /// Tunable blur behind the bubble: `blur` (0…1) scales the radius.
    func backdropParams(corner: CGFloat) -> BackdropBlurView.Params {
        .init(radius: blur * HUDStyle.maxBlurRadius, saturation: material.preset.saturation, brightness: material.brightness,
              progressive: material == .progressive, corner: corner)
    }
}

/// A diagonal gradient fill, top-left to bottom-right.
private final class GradientView: NSView {
    override func makeBackingLayer() -> CALayer { CAGradientLayer() }
    convenience init(_ colors: [NSColor], opacity: Double) {
        self.init(frame: .zero)
        wantsLayer = true
        guard let g = layer as? CAGradientLayer else { return }
        g.colors = colors.map { $0.withAlphaComponent(opacity).cgColor }
        g.startPoint = CGPoint(x: 0, y: 1)
        g.endPoint = CGPoint(x: 1, y: 0)
    }
}

extension String {
    /// A shortcut as the bubble shows it, each key apart so it reads at a glance: "⇧⌘T" → "⇧ + ⌘ + T".
    var spacedKeys: String {
        var rest = Substring(self), keys: [String] = []
        if rest.hasPrefix("fn ") { keys.append("fn"); rest = rest.dropFirst(3) }
        while let c = rest.first, "⌃⌥⇧⌘".contains(c), rest.count > 1 { keys.append(String(c)); rest = rest.dropFirst() }
        keys.append(String(rest))
        return keys.joined(separator: " + ")
    }
}

extension NSColor {
    var brightnessComponentSafe: CGFloat { (usingColorSpace(.sRGB) ?? .white).brightnessComponent }
}

/// The HUD's root: reports the pointer entering, leaving and pressing on `target` (the bubble), and lets clicks on the
/// clear margin around it fall through to whatever is underneath.
final class JellyTouchView: NSView {
    weak var target: NSView?
    var onHover: (Bool) -> Void = { _ in }
    var onPress: (Bool) -> Void = { _ in }
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        guard let target else { return }
        let a = NSTrackingArea(rect: target.frame, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(a)
        area = a
    }
    override func layout() { super.layout(); updateTrackingAreas() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let target, target.frame.contains(convert(point, from: superview)) else { return nil }
        return self
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
    override func mouseDown(with event: NSEvent) { onPress(true) }
    override func mouseUp(with event: NSEvent) { onPress(false) }
}
