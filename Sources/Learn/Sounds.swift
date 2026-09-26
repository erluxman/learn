import AppKit

/// Feedback sounds: one for clicks in Learn's UI, one for when Learn runs a shortcut. Chosen in Settings ▸ Sounds.
/// Learn's own sounds are synthesized here (no audio files); the rest are macOS's system sounds.
enum SoundEffect: String, Codable, CaseIterable, Identifiable {
    case none
    case tick, tap, pop, bubble, droplet, chime, thud                 // synthesized
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
    static let learn: [SoundEffect] = [.tick, .tap, .pop, .bubble, .droplet, .chime, .thud]
    static let system: [SoundEffect] = [.tink, .sysPop, .purr, .bottle, .morse, .glass, .ping, .frog]
}

enum Sounds {
    enum Kind { case click, shortcut }

    static func play(_ kind: Kind) {
        let look = Prefs.shared.appearance
        play(kind == .click ? look.clickSound : look.shortcutSound, volume: look.soundVolume)
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
