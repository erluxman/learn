import AppKit
import AVFoundation
import Speech

/// AI Config's ears and mouth: on-device speech recognition (never sent to a server) and macOS's voices.
/// Listening stops by itself after a short pause, or when the mic is clicked again. Main-thread only.
final class ConfigVoice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = ConfigVoice()

    @Published private(set) var listening = false
    @Published private(set) var transcript = ""
    @Published private(set) var level: Double = 0        // 0…1, for the mic's pulse
    @Published private(set) var speaking = false

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var pause: Timer?
    private var onFinish: ((String) -> Void)?
    private let synth = AVSpeechSynthesizer()
    private static let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    private static let dictationURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
    static let voicesURL = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension")!

    override private init() {
        super.init()
        synth.delegate = self
    }

    static var status: LayerStatus {
        let speech = SFSpeechRecognizer.authorizationStatus(), mic = AVCaptureDevice.authorizationStatus(for: .audio)
        if speech == .denied || speech == .restricted || mic == .denied || mic == .restricted {
            return .needsSettings("Allow in Privacy & Security",
                                  URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
        if speech != .authorized || mic != .authorized { return .needsPermission("Allow Microphone") }
        guard let r = recognizer, r.supportsOnDeviceRecognition else {
            return .needsSettings("Turn on Dictation to get the speech model", dictationURL)
        }
        return .ready
    }

    static func requestPermissions(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { s in
            AVCaptureDevice.requestAccess(for: .audio) { mic in
                DispatchQueue.main.async { done(s == .authorized && mic) }
            }
        }
    }

    // MARK: Listening

    /// Starts listening; `finish` gets what was said once the user pauses. False when it couldn't start.
    @discardableResult
    func listen(_ finish: @escaping (String) -> Void) -> Bool {
        guard !listening, let r = Self.recognizer, r.isAvailable, r.supportsOnDeviceRecognition else { return false }
        stopSpeaking()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        req.contextualStrings = ConfigSchema.all.flatMap { [$0.title] + $0.aliases.prefix(3) }   // hear "wobble", not "wobbly"

        let input = engine.inputNode, format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { return false }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            req.append(buffer)
            let level = Self.rms(buffer)
            DispatchQueue.main.async { self?.level = level }
        }
        engine.prepare()
        do { try engine.start() } catch { input.removeTap(onBus: 0); return false }

        request = req
        onFinish = finish
        transcript = ""
        listening = true
        waitForPause(6)   // nothing said at all: give up after a while
        task = r.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.listening else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal { self.stop(); return }
                    self.waitForPause(1.4)
                }
                if error != nil { self.stop() }
            }
        }
        return true
    }

    /// Stops and hands over what was heard.
    func stop() { end(deliver: true) }
    func cancel() { end(deliver: false) }

    private func end(deliver: Bool) {
        guard listening else { return }
        listening = false
        pause?.invalidate()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil; level = 0
        let said = transcript.trimmingCharacters(in: .whitespacesAndNewlines), finish = onFinish
        onFinish = nil
        if deliver, !said.isEmpty { finish?(said) }
    }

    private func waitForPause(_ seconds: TimeInterval) {
        pause?.invalidate()
        pause = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in self?.stop() }
    }

    private static func rms(_ b: AVAudioPCMBuffer) -> Double {
        guard let data = b.floatChannelData?[0], b.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(b.frameLength) { sum += data[i] * data[i] }
        return min(Double((sum / Float(b.frameLength)).squareRoot()) * 12, 1)
    }

    // MARK: Speaking

    func speak(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.voice
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.04
        synth.speak(u)
    }

    func stopSpeaking() { if synth.isSpeaking { synth.stopSpeaking(at: .immediate) } }

    /// The best English voice installed: Premium, then Enhanced, then the default one.
    static var voice: AVSpeechSynthesisVoice? {
        let lang = Locale.current.language.languageCode?.identifier == "en" ? Locale.current.identifier.replacingOccurrences(of: "_", with: "-") : "en-US"
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice) }
        return english.max { a, b in
            (a.quality.rawValue, a.language == lang ? 1 : 0) < (b.quality.rawValue, b.language == lang ? 1 : 0)
        } ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    static var voiceQuality: String {
        switch voice?.quality {
        case .premium?: "Premium voice"
        case .enhanced?: "Enhanced voice"
        default: "Basic voice"
        }
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) { DispatchQueue.main.async { self.speaking = true } }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { DispatchQueue.main.async { self.speaking = false } }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { DispatchQueue.main.async { self.speaking = false } }
}
