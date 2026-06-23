import Foundation

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let date: Date
    let appName: String?

    init(text: String, date: Date = Date(), appName: String?) {
        self.id = UUID()
        self.text = text
        self.date = date
        self.appName = appName
    }
}

/// Persists transcriptions to ~/.config/vocal/history.json (newest first, capped).
/// All disk access happens on a private serial queue; the in-memory `entries`
/// snapshot is only mutated on the main thread so the UI can read it safely.
final class HistoryStore {
    static let shared = HistoryStore()

    private let maxEntries = 1000
    private let queue = DispatchQueue(label: "local.vocal.app.history")
    private(set) var entries: [HistoryEntry] = []

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/vocal/history.json")
    }

    init() {
        load()
    }

    private func load() {
        let url = Self.fileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
    }

    /// Adds a transcription as the newest entry. Safe to call from any thread; the
    /// in-memory array is updated on main and the write is offloaded to `queue`.
    func add(text: String, appName: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let entry = HistoryEntry(text: trimmed, appName: appName)

        let commit = { [weak self] in
            guard let self else { return }
            self.entries.insert(entry, at: 0)
            if self.entries.count > self.maxEntries {
                self.entries.removeLast(self.entries.count - self.maxEntries)
            }
            self.persist()
        }
        if Thread.isMainThread { commit() } else { DispatchQueue.main.async(execute: commit) }
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    func search(_ query: String) -> [HistoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { $0.text.range(of: trimmed, options: .caseInsensitive) != nil }
    }

    private func persist() {
        let snapshot = entries
        queue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted]
            guard let data = try? encoder.encode(snapshot) else { return }
            let url = Self.fileURL
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}
