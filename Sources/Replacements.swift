import Foundation

/// A user-maintained list of known terms (brand / product names) the speech
/// models tend to mishear. Used by the on-device AI cleanup and the casing fix.
@MainActor
final class VocabularyStore: ObservableObject {
    static let shared = VocabularyStore()

    @Published var terms: [String] = [] {
        didSet { if !loading { save() } }
    }

    private let url = AppPaths.support.appendingPathComponent("vocabulary.json")
    private var loading = false

    init() { load() }

    func add() { terms.append("") }

    func remove(at index: Int) {
        guard terms.indices.contains(index) else { return }
        terms.remove(at: index)
    }

    /// Non-empty, trimmed terms.
    var activeTerms: [String] {
        terms.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func load() {
        loading = true
        defer { loading = false }
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            terms = decoded
        } else {
            terms = ["Laravel", "FlyWP", "FlyCommerce", "Dokan", "FlySend", "FlyCRM", "weDevs"]
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(terms) { try? data.write(to: url) }
    }
}

enum TextProcessor {
    /// Deterministically fixes the casing of known terms (whole-word, case-insensitive),
    /// e.g. "dokan" → "Dokan". Safe — never changes anything but capitalization of known terms.
    static func canonicalize(_ text: String, terms: [String]) -> String {
        var result = text
        for term in terms.sorted(by: { $0.count > $1.count }) {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: term) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, options: [], range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: term))
        }
        return result
    }
}
