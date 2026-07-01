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

    @Published private(set) var entries: [Entry] = []

    private let url = AppPaths.support.appendingPathComponent("history.json")
    private let limit = 1000

    init() { load() }

    func add(text: String, original: String?, language: String) {
        let originalToKeep = (original != text) ? original : nil
        entries.insert(Entry(id: UUID(), date: Date(), language: language, text: text, original: originalToKeep), at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        save()
    }

    func delete(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: url) }
    }
}
