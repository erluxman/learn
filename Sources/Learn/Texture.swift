import SwiftUI

// MARK: Blur

/// What sits behind Learn's surfaces: Liquid Glass, a tunable Gaussian blur, SwiftUI materials, AppKit's behind-window
/// materials, or nothing. Tunable blurs take `blurRadius` and `blurSaturation`; the rest are fixed by macOS, so for them
/// `blurAmount` only fades the blur in (1) or out (0).
enum BlurStyle: String, Codable, CaseIterable, Identifiable {
    case liquidRegular, liquidClear
    case gaussian, vibrant, frosted, smoked, progressive
    case ultraThin, thin, regular, thick, ultraThick
    case hud, popover, menu, sidebar, sheet, fullScreen, titlebar, header, toolTip, underWindow
    case none

    var id: Self { self }
    var title: String {
        switch self {
        case .liquidRegular: "Liquid Glass"
        case .liquidClear: "Liquid Glass — clear"
        case .gaussian: "Gaussian"
        case .vibrant: "Vibrant (Arc-style)"
        case .frosted: "Frosted milk"
        case .smoked: "Smoked"
        case .progressive: "Progressive fade"
        case .ultraThin: "Ultra thin"
        case .thin: "Thin"
        case .regular: "Regular"
        case .thick: "Thick"
        case .ultraThick: "Ultra thick"
        case .hud: "HUD"
        case .popover: "Popover"
        case .menu: "Menu"
        case .sidebar: "Sidebar"
        case .sheet: "Sheet"
        case .fullScreen: "Full-screen UI"
        case .titlebar: "Title bar"
        case .header: "Header"
        case .toolTip: "Tooltip"
        case .underWindow: "Under window"
        case .none: "None (color only)"
        }
    }
    static let liquid: [BlurStyle] = [.liquidRegular, .liquidClear]
    static let tunable: [BlurStyle] = [.gaussian, .vibrant, .frosted, .smoked, .progressive]
    static let materials: [BlurStyle] = [.ultraThin, .thin, .regular, .thick, .ultraThick]
    static let appKit: [BlurStyle] = [.hud, .popover, .menu, .sidebar, .sheet, .fullScreen, .titlebar, .header, .toolTip, .underWindow]

    var isLiquid: Bool { self == .liquidRegular || self == .liquidClear }
    var isTunable: Bool { Self.tunable.contains(self) }

    /// Radius (pt) and saturation a tunable blur starts at when picked.
    var preset: (radius: Double, saturation: Double) {
        switch self {
        case .vibrant: (8, 1.9)
        case .frosted: (7, 1.15)
        case .smoked: (8, 1.35)
        case .progressive: (10, 1.3)
        default: (5, 1.2)
        }
    }
    static let maxRadius = 10.0

    /// Brightness shift baked into the tunable blur (-1…1): milky lifts it, smoked lowers it.
    var brightness: Double {
        switch self {
        case .frosted: 0.14
        case .smoked: -0.16
        case .vibrant: 0.02
        default: 0
        }
    }

    var swiftUIMaterial: Material? {
        switch self {
        case .ultraThin: .ultraThinMaterial
        case .thin: .thinMaterial
        case .regular: .regularMaterial
        case .thick: .thickMaterial
        case .ultraThick: .ultraThickMaterial
        default: nil
        }
    }

    var appKitMaterial: NSVisualEffectView.Material? {
        switch self {
        case .hud: .hudWindow
        case .popover: .popover
        case .menu: .menu
        case .sidebar: .sidebar
        case .sheet: .sheet
        case .fullScreen: .fullScreenUI
        case .titlebar: .titlebar
        case .header: .headerView
        case .toolTip: .toolTip
        case .underWindow: .underWindowBackground
        default: nil
        }
    }
}

/// A real Gaussian blur of whatever is behind the window, at any radius — the window server's own backdrop blur
/// (`CABackdropLayer`, what NSVisualEffectView runs on), driven directly so radius, saturation and brightness are ours.
/// `progressive` fades from sharp at the bottom to fully blurred at the top. Falls back to an HUD material if the
/// private classes ever disappear.
final class BackdropBlurView: NSView {
    struct Params: Equatable {
        var radius: Double
        var saturation: Double
        var brightness = 0.0
        var progressive = false
        var corner: CGFloat = 0
    }

    private let backdrop: CALayer? = (NSClassFromString("CABackdropLayer") as? CALayer.Type)?.init()
    private var fallback: NSVisualEffectView?
    private var applied: Params?

    init(_ p: Params) {
        super.init(frame: .zero)
        wantsLayer = true
        if let b = backdrop {
            b.setValue(true, forKey: "windowServerAware")
            b.setValue(UUID().uuidString, forKey: "groupName")   // its own capture, so neighbours don't share one blur
            b.cornerCurve = .continuous
            b.masksToBounds = true
            layer?.addSublayer(b)
        } else {
            let fx = NSVisualEffectView(frame: bounds)
            fx.material = .hudWindow; fx.blendingMode = .behindWindow; fx.state = .active
            fx.autoresizingMask = [.width, .height]
            addSubview(fx)
            fallback = fx
        }
        set(p)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        backdrop?.frame = bounds
        CATransaction.commit()
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func set(_ p: Params) {
        guard p != applied else { return }
        applied = p
        fallback?.layer?.cornerRadius = p.corner
        guard let b = backdrop else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        b.cornerRadius = p.corner
        b.isHidden = p.radius < 0.5 && p.saturation == 1 && p.brightness == 0
        // Larger radii are blurred at half resolution: indistinguishable, and far cheaper for the window server.
        b.setValue(p.radius > 6 ? 0.5 : 1.0, forKey: "scale")
        var filters: [NSObject] = []
        if p.radius >= 0.5 {
            if p.progressive, let blur = Self.filter("variableBlur") {
                blur.setValue(p.radius, forKey: "inputRadius")
                blur.setValue(Self.fadeMask, forKey: "inputMaskImage")
                blur.setValue(true, forKey: "inputNormalizeEdges")
                filters.append(blur)
            } else if let blur = Self.filter("gaussianBlur") {
                blur.setValue(p.radius, forKey: "inputRadius")
                blur.setValue(true, forKey: "inputNormalizeEdges")   // no dark fringe at the edges
                filters.append(blur)
            }
        }
        if p.saturation != 1, let sat = Self.filter("colorSaturate") {
            sat.setValue(p.saturation, forKey: "inputAmount"); filters.append(sat)
        }
        if p.brightness != 0, let br = Self.filter("colorBrightness") {
            br.setValue(p.brightness, forKey: "inputAmount"); filters.append(br)
        }
        b.filters = filters
    }

    private static func filter(_ type: String) -> NSObject? {
        guard let cls = NSClassFromString("CAFilter") as? NSObject.Type,
              cls.responds(to: NSSelectorFromString("filterWithType:")) else { return nil }
        return cls.perform(NSSelectorFromString("filterWithType:"), with: type)?.takeUnretainedValue() as? NSObject
    }

    /// Alpha ramp for the variable blur: opaque (full blur) at the top, clear (sharp) at the bottom.
    private static let fadeMask: CGImage? = {
        guard let ctx = CGContext(data: nil, width: 1, height: 128, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
              let g = CGGradient(colorsSpace: nil, colors: [CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 0)] as CFArray, locations: [0.1, 1])
        else { return nil }
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 128), end: .zero, options: [])
        return ctx.makeImage()
    }()
}

/// SwiftUI face of `BackdropBlurView`.
struct BackdropBlur: NSViewRepresentable {
    let params: BackdropBlurView.Params
    func makeNSView(context: Context) -> BackdropBlurView { BackdropBlurView(params) }
    func updateNSView(_ v: BackdropBlurView, context: Context) { v.set(params) }
}

/// AppKit behind-window blur in a rounded shape (a mask image — SwiftUI clipping doesn't reach the window server's blur).
struct BehindWindowBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let radius: CGFloat
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.maskImage = Self.mask(radius)
    }
    private static var masks: [CGFloat: NSImage] = [:]
    static func mask(_ r: CGFloat) -> NSImage {
        if let m = masks[r] { return m }
        let side = 2 * r + 1
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        img.resizingMode = .stretch
        masks[r] = img
        return img
    }
}

// MARK: Grain

/// Texture laid on the glass, generated once (per size) as a seamless tile.
/// The noises follow what makes grain look expensive rather than like TV static: Gaussian (not uniform) values centred
/// on mid-grey and blended with overlay, so they add texture without brightening or darkening the glass; one sample per
/// display pixel; and spectra shaped for the look — blue noise (high-passed, no clumps), film (fine + clumped
/// silver), fractal turbulence (the SVG feTurbulence "grainy gradient"), paper (soft fibres under fine tooth).
enum GrainStyle: String, Codable, CaseIterable, Identifiable {
    case none, fine, blue, film, turbulence, paper, color
    case halftone, linen, dither, scanlines, glitter

    static let noises: [GrainStyle] = [.fine, .blue, .film, .turbulence, .paper, .color]
    static let patterns: [GrainStyle] = [.halftone, .linen, .dither, .scanlines, .glitter]

    /// Styles removed since (coarse, sand, fibers, clouds) map to their closest successor.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        let legacy = ["coarse": "film", "sand": "fine", "fibers": "paper", "clouds": "turbulence"]
        self = GrainStyle(rawValue: legacy[raw] ?? raw) ?? .fine
    }

    var id: Self { self }
    var title: String {
        switch self {
        case .none: "None"
        case .fine: "Fine grain"
        case .blue: "Blue noise"
        case .film: "Film grain"
        case .turbulence: "Fractal (grainy gradient)"
        case .paper: "Paper"
        case .color: "Color grain"
        case .halftone: "Halftone"
        case .linen: "Linen"
        case .dither: "Dither"
        case .scanlines: "Scanlines"
        case .glitter: "Glitter"
        }
    }

    var blend: BlendMode {
        switch self {
        case .glitter: .plusLighter
        case .paper, .turbulence: .softLight
        default: .overlay
        }
    }

    /// How opaque the texture gets at 100% amount (some read strong, some faint).
    var strength: Double {
        switch self {
        case .fine, .blue, .film, .color: 0.9
        case .turbulence, .paper: 1
        case .halftone, .linen, .scanlines, .dither: 0.3
        case .glitter: 0.6
        case .none: 0
        }
    }

    private static var cache: [String: NSImage] = [:]

    var isNoise: Bool { Self.noises.contains(self) }

    /// How the tile is laid on the glass: grey grain by its own blend; colored grain is drawn as-is (its color is the point).
    func blend(colored: Bool) -> BlendMode { colored ? .normal : blend }

    /// Seamless tile; `scale` (0.5…3) makes the grain larger. 1× = one grain per Retina pixel.
    /// With a `color`, the grain is that color: noise grains lighter than average take the color, darker ones a deep
    /// shade of it, each as opaque as it is far from average — so the texture reads in the color without washing the glass.
    func tile(scale: Double, color: HUDStyle.RGBA? = nil) -> NSImage? {
        guard self != .none else { return nil }
        let s = (scale * 4).rounded() / 4
        let key = "\(rawValue)|\(s)|" + (color.map { String(format: "%.3f,%.3f,%.3f", $0.r, $0.g, $0.b) } ?? "")
        if let img = Self.cache[key] { return img }
        let n = 256
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(ctx, n)
        if let color { tint(ctx, n, color) }
        guard let cg = ctx.makeImage() else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: Double(n) * s / 2, height: Double(n) * s / 2))   // 2 px per pt at 1×
        Self.cache[key] = img
        return img
    }

    private func draw(_ ctx: CGContext, _ n: Int) {
        var rng = SplitMix(seed: rawValue.utf8.reduce(1469598103934665603) { ($0 ^ UInt64($1)) &* 1099511628211 })
        func rnd() -> Double { rng.unit() }
        func gray(_ v: Double, _ a: Double) -> CGColor { CGColor(srgbRed: v, green: v, blue: v, alpha: a) }
        let size = CGFloat(n)
        let px = ctx.data!.bindMemory(to: UInt8.self, capacity: n * n * 4)
        /// Writes zero-mean, unit-variance fields as opaque grey around 0.5 (`contrast` = one standard deviation).
        func put(_ r: [Double], _ g: [Double]? = nil, _ b: [Double]? = nil, contrast: Double) {
            let g = g ?? r, b = b ?? r
            for i in 0..<(n * n) {
                px[i * 4] = Self.byte(0.5 + r[i] * contrast)
                px[i * 4 + 1] = Self.byte(0.5 + g[i] * contrast)
                px[i * 4 + 2] = Self.byte(0.5 + b[i] * contrast)
                px[i * 4 + 3] = 255
            }
        }
        func gaussian() -> [Double] { (0..<(n * n)).map { _ in rng.gaussian() } }
        switch self {
        case .none: return
        case .fine:
            put(gaussian(), contrast: 0.13)
        case .blue:     // white noise minus its blur: only the high frequencies stay, so grains never clump
            let w = gaussian()
            let low = Self.boxBlur(Self.boxBlur(w, n, 1), n, 1)
            put(Self.normalized(zip(w, low).map { $0 - $1 }), contrast: 0.14)
        case .film:     // fine grain riding on softly clumped grain, like developed silver
            let fine = gaussian(), clumps = Self.normalized(Self.boxBlur(gaussian(), n, 1))
            put(Self.normalized(zip(fine, clumps).map { $0 * 0.7 + $1 * 0.5 }), contrast: 0.11)
        case .turbulence:   // fractal value noise at 2–16 px periods: the grainy-gradient texture
            let octaves: [(cells: Int, weight: Double)] = [(128, 0.45), (64, 0.3), (32, 0.17), (16, 0.08)]
            let grids = octaves.map { o in (0..<(o.cells * o.cells)).map { _ in rnd() } }
            var f = [Double](repeating: 0, count: n * n)
            for y in 0..<n {
                for x in 0..<n {
                    let u = Double(x) / Double(n), v = Double(y) / Double(n)
                    for k in 0..<octaves.count { f[y * n + x] += Self.valueNoise(u, v, octaves[k].cells, grids[k]) * octaves[k].weight }
                }
            }
            put(Self.normalized(f), contrast: 0.16)
        case .paper:    // slow cloudy fibre density under a fine tooth
            let octaves: [(cells: Int, weight: Double)] = [(8, 0.5), (16, 0.3), (32, 0.2)]
            let grids = octaves.map { o in (0..<(o.cells * o.cells)).map { _ in rnd() } }
            var f = [Double](repeating: 0, count: n * n)
            for y in 0..<n {
                for x in 0..<n {
                    let u = Double(x) / Double(n), v = Double(y) / Double(n)
                    for k in 0..<octaves.count { f[y * n + x] += Self.valueNoise(u, v, octaves[k].cells, grids[k]) * octaves[k].weight }
                }
            }
            let tooth = Self.normalized(Self.boxBlur(gaussian(), n, 1))
            put(Self.normalized(zip(Self.normalized(f), tooth).map { $0 * 0.45 + $1 * 0.8 }), contrast: 0.12)
        case .color:    // mostly luminance with a little independent chroma per channel, as camera sensors show it
            let l = gaussian()
            let r = Self.normalized(zip(l, gaussian()).map { $0 + $1 * 0.55 })
            let g = Self.normalized(zip(l, gaussian()).map { $0 + $1 * 0.55 })
            let b = Self.normalized(zip(l, gaussian()).map { $0 + $1 * 0.55 })
            put(r, g, b, contrast: 0.13)
        case .linen:    // woven cross-hatch with slub
            for i in stride(from: 0, to: n, by: 2) {
                ctx.setFillColor(gray(1, 0.1 + rnd() * 0.25))
                ctx.fill(CGRect(x: 0, y: i, width: n, height: 1))
                ctx.setFillColor(gray(0, 0.1 + rnd() * 0.25))
                ctx.fill(CGRect(x: i, y: 0, width: 1, height: n))
            }
        case .halftone: // dot grid, dot size drifting smoothly
            let step = 8
            ctx.setFillColor(gray(0, 0.75))
            for y in stride(from: 0, to: n, by: step) {
                for x in stride(from: 0, to: n, by: step) {
                    let wave: Double = sin(Double(x) / Double(n) * 2 * .pi) + cos(Double(y) / Double(n) * 2 * .pi)
                    let r: Double = 1 + (wave + 2) / 4 * 2.4
                    ctx.fillEllipse(in: CGRect(x: Double(x) + 4 - r, y: Double(y) + 4 - r, width: r * 2, height: r * 2))
                }
            }
        case .dither:   // 4×4 Bayer ordered pattern
            let bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
            ctx.setFillColor(gray(0, 0.85))
            for y in 0..<n {
                for x in 0..<n where bayer[(y % 4) * 4 + x % 4] < 8 { ctx.fill(CGRect(x: x, y: y, width: 1, height: 1)) }
            }
        case .scanlines:
            ctx.setFillColor(gray(0, 0.55))
            for y in stride(from: 0, to: n, by: 3) { ctx.fill(CGRect(x: 0, y: y, width: n, height: 1)) }
        case .glitter:  // bright points, some with a small 4-point star
            for _ in 0..<160 {
                let x = rnd() * size, y = rnd() * size, big = rnd() > 0.8
                ctx.setFillColor(gray(1, 0.5 + rnd() * 0.5))
                ctx.fillEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
                if big {
                    ctx.setFillColor(gray(1, 0.35))
                    ctx.fill(CGRect(x: x - 4, y: y - 0.3, width: 8, height: 0.6))
                    ctx.fill(CGRect(x: x - 0.3, y: y - 4, width: 0.6, height: 8))
                }
            }
        }
    }

    private func tint(_ ctx: CGContext, _ n: Int, _ c: HUDStyle.RGBA) {
        let px = ctx.data!.bindMemory(to: UInt8.self, capacity: n * n * 4)
        let light = [c.r, c.g, c.b], dark = light.map { $0 * 0.3 }
        for i in 0..<(n * n) {
            let p = i * 4
            let a = Double(px[p + 3]) / 255
            guard a > 0 else { continue }
            let lum = (Double(px[p]) * 0.299 + Double(px[p + 1]) * 0.587 + Double(px[p + 2]) * 0.114) / 255 / a   // un-premultiplied
            let rgb: [Double], alpha: Double
            if isNoise {   // centred on grey: distance from it is the grain
                let d = (lum - 0.5) * 3
                (rgb, alpha) = (d >= 0 ? light : dark, min(1, abs(d)))
            } else {       // patterns: their shape keeps its alpha, the color follows its lightness
                (rgb, alpha) = (light.map { $0 * (0.35 + 0.65 * lum) }, a)
            }
            for k in 0..<3 { px[p + k] = Self.byte(rgb[k] * alpha) }
            px[p + 3] = Self.byte(alpha)
        }
    }

    private static func byte(_ v: Double) -> UInt8 { UInt8(max(0, min(1, v)) * 255 + 0.5) }

    /// Shifted and scaled to mean 0, standard deviation 1.
    private static func normalized(_ f: [Double]) -> [Double] {
        let mean = f.reduce(0, +) / Double(f.count)
        let sd = (f.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(f.count)).squareRoot()
        return f.map { ($0 - mean) / max(sd, 1e-9) }
    }

    /// (2r+1)² box average, wrapping at the edges so the tile stays seamless.
    private static func boxBlur(_ f: [Double], _ n: Int, _ r: Int) -> [Double] {
        var h = [Double](repeating: 0, count: n * n), out = h
        let k = Double(2 * r + 1)
        for y in 0..<n { for x in 0..<n { var s = 0.0; for d in -r...r { s += f[y * n + (x + d + n) % n] }; h[y * n + x] = s / k } }
        for y in 0..<n { for x in 0..<n { var s = 0.0; for d in -r...r { s += h[((y + d + n) % n) * n + x] }; out[y * n + x] = s / k } }
        return out
    }

    /// Smoothly interpolated random grid of `g`×`g` cells, wrapping at the edges; `u`, `v` in 0…1.
    private static func valueNoise(_ u: Double, _ v: Double, _ g: Int, _ cells: [Double]) -> Double {
        let fx = u * Double(g), fy = v * Double(g)
        let x0 = Int(fx) % g, y0 = Int(fy) % g
        let x1 = (x0 + 1) % g, y1 = (y0 + 1) % g
        let tx = fx - fx.rounded(.down), ty = fy - fy.rounded(.down)
        let sx: Double = tx * tx * (3 - 2 * tx)
        let sy: Double = ty * ty * (3 - 2 * ty)
        let top: Double = cells[y0 * g + x0] * (1 - sx) + cells[y0 * g + x1] * sx
        let bottom: Double = cells[y1 * g + x0] * (1 - sx) + cells[y1 * g + x1] * sx
        return top * (1 - sy) + bottom * sy
    }
}

/// Small fast seeded generator: uniform and Gaussian (Box–Muller) samples.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func gaussian() -> Double {
        let u = max(unit(), 1e-12), v = unit()
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
    }
}
