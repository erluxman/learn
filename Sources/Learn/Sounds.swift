import AppKit

/// Feedback: a sound and a trackpad tap for clicks in Learn's UI, and for when Learn runs a shortcut. Volume in Settings ▸ General.
/// Learn's own sounds are synthesized here (no audio files); the rest are macOS's system sounds.
enum SoundEffect: String, Codable, CaseIterable, Identifiable {
    case none
    case tick, tap, pop, bubble, droplet, chime, thud, coin           // synthesized
    case tink, sysPop, purr, bottle, morse, glass, ping, frog         // /System/Library/Sounds

    var id: Self { self }
    var title: String {
        switch self {
        case .none: "None"
        case .tick: "Tick"
        case .tap: "Tap"
        case .pop: "Pop"
        case .bubble: "Bubble"
        case .droplet: "Droplet"
        case .chime: "Glass chime"
        case .thud: "Soft thud"
        case .coin: "Coin"
        case .tink: "Tink"
        case .sysPop: "Pop (macOS)"
        case .purr: "Purr"
        case .bottle: "Bottle"
        case .morse: "Morse"
        case .glass: "Glass"
        case .ping: "Ping"
        case .frog: "Frog"
        }
    }
    static let learn: [SoundEffect] = [.tick, .tap, .pop, .bubble, .droplet, .chime, .thud, .coin]
    static let system: [SoundEffect] = [.tink, .sysPop, .purr, .bottle, .morse, .glass, .ping, .frog]
}

enum Sounds {
    enum Kind { case click, shortcut }

    private static var lastClick: CFTimeInterval = 0
    private static var lastTick: CFTimeInterval = 0

    static func play(_ kind: Kind) {
        let look = Prefs.shared.appearance
        if kind == .click {   // a control with its own sound and the app-wide feedback below can both fire: one sound
            let now = CACurrentMediaTime()
            guard now - lastClick > 0.08 else { return }
            lastClick = now
        }
        play(kind == .click ? look.clickSound : look.shortcutSound, volume: look.soundVolume)
        feel(kind == .click ? .generic : .levelChange)
    }

    /// A tap you feel on a Force Touch trackpad, alongside the sound (not tied to the volume, so it works when muted).
    /// macOS only plays it while a finger is on the trackpad; a mouse has no haptics.
    private static func feel(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    /// Soft detent while a slider is dragged: the click sound, quieter, at most every 35 ms.
    static func tick() {
        let now = CACurrentMediaTime(), look = Prefs.shared.appearance
        guard now - lastTick > 0.035, now - lastClick > 0.08 else { return }
        lastTick = now
        play(look.clickSound, volume: look.soundVolume * 0.45)
        feel(.alignment)   // slider detents: a light tick under the finger
    }

    // MARK: App-wide feedback

    private static var monitor: Any?

    /// Every interaction in Learn's windows clicks: pressing any native control (switch, segmented tabs, checkbox,
    /// slider grab, color well, stepper), opening any menu (pickers, pop-ups, context menus) and choosing from it.
    /// Custom glass buttons already click themselves; the de-dupe in `play` keeps it to one sound.
    static func installFeedback() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            if let root = event.window?.contentView, let hit = root.hitTest(event.locationInWindow),
               isControl(hit) {
                play(.click)
            }
            return event
        }
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in play(.click) }
        nc.addObserver(forName: NSMenu.didSendActionNotification, object: nil, queue: .main) { _ in play(.click) }
    }

    /// A native control, or a view inside one. Pop-up buttons are left to the menu they open.
    private static func isControl(_ v: NSView) -> Bool {
        var view: NSView? = v
        while let c = view {
            if c is NSPopUpButton { return false }
            if c is NSControl || c is NSSwitch { return (c as? NSControl)?.isEnabled ?? true }
            view = c.superview
        }
        return false
    }

    static func play(_ effect: SoundEffect, volume: Double) {
        guard effect != .none, volume > 0, let sound = sound(effect) else { return }
        sound.stop()   // rapid clicks restart rather than pile up
        sound.volume = Float(volume)
        sound.play()
    }

    private static var cache: [SoundEffect: NSSound] = [:]

    static func sound(_ e: SoundEffect) -> NSSound? {
        if let s = cache[e] { return s }
        let s: NSSound?
        switch e {
        case .none: s = nil
        case .tink: s = NSSound(named: "Tink")
        case .sysPop: s = NSSound(named: "Pop")
        case .purr: s = NSSound(named: "Purr")
        case .bottle: s = NSSound(named: "Bottle")
        case .morse: s = NSSound(named: "Morse")
        case .glass: s = NSSound(named: "Glass")
        case .ping: s = NSSound(named: "Ping")
        case .frog: s = NSSound(named: "Frog")
        default: s = NSSound(data: wav(synth(e)))
        }
        cache[e] = s
        return s
    }

    // MARK: Synthesis

    private static let rate = 44_100.0

    /// Samples in -1…1 for Learn's own sounds.
    private static func synth(_ e: SoundEffect) -> [Double] {
        func render(_ seconds: Double, _ f: (Double) -> Double) -> [Double] {
            (0..<Int(seconds * rate)).map { f(Double($0) / rate) }
        }
        func env(_ t: Double, attack: Double, decay: Double) -> Double { min(t / attack, 1) * exp(-t / decay) }
        var phase = 0.0
        func sweep(_ t: Double, from: Double, to: Double, over: Double) -> Double {   // phase-continuous glide
            let f = from + (to - from) * min(t / over, 1)
            phase += 2 * .pi * f / rate
            return sin(phase)
        }
        switch e {
        case .tick:   // crisp, tiny: a click of high partials
            return render(0.03) { t in (0.6 * sin(2 * .pi * 3_800 * t) + 0.4 * sin(2 * .pi * 6_100 * t)) * env(t, attack: 0.0004, decay: 0.006) }
        case .tap:    // soft wooden tap
            return render(0.07) { t in sweep(t, from: 1_300, to: 900, over: 0.03) * env(t, attack: 0.001, decay: 0.016) }
        case .pop:    // round pop, pitch rising
            return render(0.09) { t in sweep(t, from: 380, to: 1_050, over: 0.05) * env(t, attack: 0.002, decay: 0.022) }
        case .bubble: // two quick rising blips
            return render(0.14) { t in
                let second = t > 0.055 ? t - 0.055 : -1
                let a = sweep(t, from: 600, to: 1_300, over: 0.04) * env(t, attack: 0.002, decay: 0.014)
                let b = second < 0 ? 0 : sin(2 * .pi * (900 + 900 * min(second / 0.04, 1)) * second) * env(second, attack: 0.002, decay: 0.018)
                return a + 0.8 * b
            }
        case .droplet: // water drop: fast upward glide
            return render(0.12) { t in sweep(t, from: 900, to: 2_600, over: 0.035) * env(t, attack: 0.001, decay: 0.03) }
        case .chime:  // glass: bell-like inharmonic partials, long tail
            return render(0.6) { t in
                (sin(2 * .pi * 1_760 * t) + 0.5 * sin(2 * .pi * 2_640 * t) + 0.3 * sin(2 * .pi * 4_220 * t))
                    / 1.8 * env(t, attack: 0.002, decay: 0.16)
            }
        case .thud:   // soft, low, muted
            return render(0.1) { t in sweep(t, from: 180, to: 90, over: 0.06) * env(t, attack: 0.002, decay: 0.03) }
        case .coin:   // game coin pickup: a short B5, then a ringing E6 — square-ish (odd harmonics), softened
            func square(_ f: Double, _ t: Double) -> Double {
                (sin(2 * .pi * f * t) + sin(2 * .pi * 3 * f * t) / 3 + sin(2 * .pi * 5 * f * t) / 5 + sin(2 * .pi * 7 * f * t) / 7) / 1.4
            }
            let step = 0.075
            return render(0.55) { t in
                t < step ? square(987.77, t) * 0.55 * min(t / 0.002, 1)
                         : square(1_318.51, t - step) * 0.55 * exp(-(t - step) / 0.16) * min((t - step) / 0.002, 1)
            }
        default:
            return []
        }
    }

    /// 16-bit mono PCM WAV.
    private static func wav(_ samples: [Double]) -> Data {
        var d = Data()
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); put(36 + bytes)
        d.append(contentsOf: Array("WAVEfmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(UInt32(rate)); put(UInt32(rate * 2)); put(UInt16(2)); put(UInt16(16))
        d.append(contentsOf: Array("data".utf8)); put(bytes)
        for s in samples { put(Int16(max(-1, min(1, s)) * 0.9 * Double(Int16.max))) }
        return d
    }
}

