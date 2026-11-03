import CoreML
import Foundation

/// AI Config's understanding: a small sentence-embedding model (paraphrase-MiniLM-L3, 17M parameters, Core ML, in the
/// app) turns any sentence into a meaning vector. Every intent in intents.json comes with example sentences; what the
/// user says goes to the intent whose examples mean the closest thing. "I don't want that menu", "that menu is not
/// necessary" and "menu items are clutter" land on the same intent without sharing a word.
final class SemanticModel {
    static let shared = SemanticModel()

    struct Intent: Decodable {
        let id: String
        var setting: String? = nil      // a setting intent: which setting …
        var op: String? = nil           // … and what to do (on, off, more, less, reset, change, color, away, choice:<id>)
        var command: String? = nil      // or a command (undo, help, shortcut.create, none, …)
        let chip: String                // how a button offering it reads
        let reply: String               // what AI Config says after doing it
        var examples: [String]
    }
    struct Match { let intent: Intent; let score: Float }

    private(set) var intents: [Intent] = []
    private var vectors: [(intent: Int, vector: [Float])] = []
    private var model: MLModel?
    private var vocab: [String: Int32] = [:]
    private let queue = DispatchQueue(label: "learn.semantic", qos: .userInitiated)
    private(set) var ready = false
    private(set) var failure: String?

    /// Where the model lives: the app's Resources/AIConfig, or (running from `swift run`) the repo's.
    private static var folder: URL? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("AIConfig")
        if let b = bundled, FileManager.default.fileExists(atPath: b.appendingPathComponent("intents.json").path) { return b }
        let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/AIConfig")
        return FileManager.default.fileExists(atPath: repo.appendingPathComponent("intents.json").path) ? repo : nil
    }
    private static let learnedFile = ShortcutStore.shared.dir.deletingLastPathComponent().appendingPathComponent("learned-intents.json")

    /// Loads the model and embeds every example, off the main thread; `done` runs on main.
    func load(_ done: @escaping () -> Void = {}) {
        queue.async { [self] in
            if !ready && failure == nil {
                do { try loadSync() } catch { failure = error.localizedDescription }
            }
            DispatchQueue.main.async(execute: done)
        }
    }

    private func loadSync() throws {
        guard let dir = Self.folder else { throw Failure("The semantic model isn't in this build. Build with ./build.sh.") }
        let words = try String(contentsOf: dir.appendingPathComponent("vocab.txt"), encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
        for (i, w) in words.enumerated() { vocab[String(w)] = Int32(i) }
        let compiled = dir.appendingPathComponent("IntentEncoder.mlmodelc")
        let url = FileManager.default.fileExists(atPath: compiled.path) ? compiled
            : try MLModel.compileModel(at: dir.appendingPathComponent("IntentEncoder.mlpackage"))
        let cfg = MLModelConfiguration()
        cfg.computeUnits = .cpuAndNeuralEngine
        model = try MLModel(contentsOf: url, configuration: cfg)

        struct File: Decodable { let intents: [Intent] }
        intents = try JSONDecoder().decode(File.self, from: Data(contentsOf: dir.appendingPathComponent("intents.json"))).intents
        let learned = (try? JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: Self.learnedFile))) ?? [:]
        for (id, examples) in learned { if let i = intents.firstIndex(where: { $0.id == id }) { intents[i].examples += examples } }
        vectors = intents.enumerated().flatMap { i, intent in intent.examples.compactMap { embed($0).map { (i, $0) } } }
        ready = true
    }

    private struct Failure: LocalizedError { let errorDescription: String?; init(_ s: String) { errorDescription = s } }

    /// Every intent, best first, scored by its closest example (cosine similarity, 0…1). Empty until loaded.
    func rank(_ text: String, among allowed: ((Intent) -> Bool)? = nil) -> [Match] {
        guard ready else { return [] }
        return queue.sync {
            guard let q = embed(text) else { return [] }
            var best = [Float](repeating: -1, count: intents.count)
            for (i, v) in vectors where allowed?(intents[i]) ?? true {
                var dot: Float = 0
                for k in 0..<min(q.count, v.count) { dot += q[k] * v[k] }
                best[i] = max(best[i], dot)
            }
            return best.enumerated().filter { $0.element > -1 }.sorted { $0.element > $1.element }.map { Match(intent: intents[$0.offset], score: $0.element) }
        }
    }

    /// Teaches it: `text` means `id` from now on (the user picked it from a "did you mean").
    func learn(_ text: String, as id: String) {
        queue.async { [self] in
            guard let i = intents.firstIndex(where: { $0.id == id }), !intents[i].examples.contains(text), let v = embed(text) else { return }
            intents[i].examples.append(text)
            vectors.append((i, v))
            var learned = (try? JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: Self.learnedFile))) ?? [:]
            learned[id, default: []].append(text)
            try? JSONEncoder().encode(learned).write(to: Self.learnedFile, options: .atomic)
        }
    }

    // MARK: Model

    private static let length = 64

    private func embed(_ text: String) -> [Float]? {
        guard let model else { return nil }
        let ids = tokenize(text)
        guard let input = try? MLMultiArray(shape: [1, NSNumber(value: Self.length)], dataType: .int32),
              let mask = try? MLMultiArray(shape: [1, NSNumber(value: Self.length)], dataType: .int32) else { return nil }
        for i in 0..<Self.length {
            input[i] = NSNumber(value: i < ids.count ? ids[i] : 0)
            mask[i] = NSNumber(value: i < ids.count ? 1 : 0)
        }
        guard let features = try? MLDictionaryFeatureProvider(dictionary: ["input_ids": input, "attention_mask": mask]),
              let out = try? model.prediction(from: features).featureValue(for: "embedding")?.multiArrayValue else { return nil }
        return (0..<out.count).map { out[$0].floatValue }
    }

    /// BERT's uncased WordPiece: lowercase, drop accents, split off punctuation, then longest known pieces ("##" inside a word).
    private func tokenize(_ text: String) -> [Int32] {
        let cls: Int32 = 101, sep: Int32 = 102, unk: Int32 = 100
        let plain = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        var words: [String] = [], word = ""
        for ch in plain {
            if ch.isWhitespace { if !word.isEmpty { words.append(word); word = "" } }
            else if ch.isPunctuation || ch.isSymbol { if !word.isEmpty { words.append(word); word = "" }; words.append(String(ch)) }
            else { word.append(ch) }
        }
        if !word.isEmpty { words.append(word) }

        var ids: [Int32] = [cls]
        for w in words {
            let chars = Array(w)
            var start = 0, pieces: [Int32] = []
            while start < chars.count {
                var end = chars.count, hit: Int32?
                while start < end {
                    let piece = (start > 0 ? "##" : "") + String(chars[start..<end])
                    if let id = vocab[piece] { hit = id; break }
                    end -= 1
                }
                guard let hit else { pieces = [unk]; break }
                pieces.append(hit)
                start = end
            }
            ids += pieces
            if ids.count >= Self.length - 1 { break }
        }
        return Array(ids.prefix(Self.length - 1)) + [sep]
    }
}
