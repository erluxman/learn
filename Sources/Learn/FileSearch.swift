import AppKit
import UniformTypeIdentifiers

struct FileHit: Hashable {
    let url: URL
    let name: String
    let type: String?     // UTI, for the icon (no file access → no Desktop/Documents prompts)
    let lastUsed: Date?
    let score: Int        // Fuzzy rank of the name; -1 = matched on contents only

    var folder: String { (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath }
    var icon: NSImage { NSWorkspace.shared.icon(for: type.flatMap(UTType.init) ?? .data) }
}

/// Files in the home folder via the Spotlight index (NSMetadataQuery — what `mdfind` uses). Main-thread only.
/// Best name matches first (same tiers as Learn's list), then content-only matches; recent files win ties.
final class FileSearch {
    var onResults: ([FileHit]) -> Void = { _ in }
    private var query: NSMetadataQuery?
    private var pending: DispatchWorkItem?
    private var text = ""
    private var observers: [NSObjectProtocol] = []

    func search(_ q: String) {
        let q = q.trimmingCharacters(in: .whitespaces)
        guard q != text else { return }
        text = q
        pending?.cancel()
        stop()
        guard q.count >= 2 else { return }   // the model already cleared its file rows
        let work = DispatchWorkItem { [weak self] in self?.start(q) }   // wait for a typing pause
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func cancel() { pending?.cancel(); stop(); text = "" }

    private func start(_ q: String) {
        // Spotlight query syntax: every word must start a word in the name (cdw = case/diacritic-insensitive, word-based),
        // or the whole phrase appears in the contents.
        let safe = q.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "*", with: "")
        let words = safe.split(separator: " ").map { "kMDItemDisplayName == \"\($0)*\"cdw" }.joined(separator: " && ")
        guard !words.isEmpty,
              let pred = NSPredicate(fromMetadataQueryString: "(\(words)) || kMDItemTextContent == \"\(safe)*\"cdw") else { return }
        let mq = NSMetadataQuery()
        mq.predicate = pred
        mq.searchScopes = [NSMetadataQueryUserHomeScope]
        mq.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false)]
        mq.notificationBatchingInterval = 0.15
        let nc = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryGatheringProgress, .NSMetadataQueryDidUpdate] {
            observers.append(nc.addObserver(forName: name, object: mq, queue: .main) { [weak self] _ in self?.collect(mq, q) })
        }
        query = mq
        mq.start()
    }

    private func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        query?.stop()
        query = nil
    }

    private func collect(_ mq: NSMetadataQuery, _ q: String) {
        guard mq === query else { return }
        mq.disableUpdates()
        defer { mq.enableUpdates() }
        var hits: [FileHit] = []
        for i in 0..<min(mq.resultCount, 400) {
            guard let item = mq.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            if path.contains("/Library/") || path.contains("/.") || path.contains("/node_modules/") || path.hasSuffix(".app") { continue }
            let name = item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String ?? (path as NSString).lastPathComponent
            hits.append(FileHit(url: URL(fileURLWithPath: path), name: name,
                                type: item.value(forAttribute: NSMetadataItemContentTypeKey) as? String,
                                lastUsed: item.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date,
                                score: Fuzzy.rank(q, title: name).map { $0 / 1000 } ?? -1))
        }
        let ranked = hits.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast)
        }
        onResults(Array(ranked.prefix(40)))
    }
}
