import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    struct Entry: Identifiable, Codable, Equatable {
        let id: UUID
        let date: Date
        let language: String
        let text: String          // final inserted text
        var original: String?     // pre-cleanup transcript, only when cleanup changed it
    }

    /// Lifetime totals, kept separate from `entries` so they survive a history clear.
    struct Stats: Codable {
        var dictations = 0
        var words = 0
        var characters = 0
        var wordsByLanguage: [String: Int] = [:]
        var secondsByModel: [String: Double] = [:]   // model id → total audio seconds sent
        var firstUse: Date?

        /// Rough time saved vs. typing, in seconds. Typing ≈ 40 wpm, speaking ≈ 150 wpm.
        var timeSavedSeconds: Double {
            Double(words) * 60.0 * (1.0 / 40.0 - 1.0 / 150.0)
        }
        var averageWords: Int { dictations > 0 ? words / dictations : 0 }
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var stats = Stats()

    private let entriesStore = JSONStore<[Entry]>("history.json")
    private let statsStore = JSONStore<Stats>("stats.json")
    private let limit = 1000

    init() { load() }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    func add(text: String, original: String?, language: String) {
        let originalToKeep = (original != text) ? original : nil
        entries.insert(Entry(id: UUID(), date: Date(), language: language, text: text, original: originalToKeep), at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        save()

        let words = HistoryStore.wordCount(text)
        stats.dictations += 1
        stats.words += words
        stats.characters += text.count
        stats.wordsByLanguage[language, default: 0] += words
        if stats.firstUse == nil { stats.firstUse = Date() }
        saveStats()
    }

    /// Record how much audio was sent to a given model (for usage/cost reporting).
    func recordAudio(modelID: String, seconds: Double) {
        guard seconds > 0 else { return }
        stats.secondsByModel[modelID, default: 0] += seconds
        saveStats()
    }

    func delete(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    func resetStats() {
        stats = Stats()
        saveStats()
    }

    private func load() {
        entries = entriesStore.load() ?? []
        if let saved = statsStore.load() {
            stats = saved
        } else if !entries.isEmpty {
            // First run with the stats feature: seed from whatever history we already have.
            seedStatsFromHistory()
            saveStats()
        }
    }

    private func seedStatsFromHistory() {
        var seeded = Stats()
        for entry in entries {
            let words = HistoryStore.wordCount(entry.text)
            seeded.dictations += 1
            seeded.words += words
            seeded.characters += entry.text.count
            seeded.wordsByLanguage[entry.language, default: 0] += words
        }
        seeded.firstUse = entries.last?.date
        stats = seeded
    }

    private func save() { entriesStore.save(entries) }
    private func saveStats() { statsStore.save(stats) }
}
