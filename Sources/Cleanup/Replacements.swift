import Foundation

/// A user-maintained list of known terms (brand / product names) the speech
/// models tend to mishear. Used by the on-device AI cleanup and the casing fix.
@MainActor
final class VocabularyStore: ObservableObject {
    static let shared = VocabularyStore()

    @Published var terms: [String] = [] {
        didSet { if !loading { save() } }
    }

    private let store = JSONStore<[String]>("vocabulary.json")
    private var loading = false

    init() { load() }

    /// Add a term, trimmed and de-duplicated (case-insensitive). No-op if blank/duplicate.
    func add(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !terms.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        terms.append(trimmed)
    }

    func remove(_ term: String) { terms.removeAll { $0 == term } }

    /// Non-empty, trimmed terms.
    var activeTerms: [String] {
        terms.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func load() {
        loading = true
        defer { loading = false }
        terms = store.load() ?? ["Laravel", "FlyWP", "FlyCommerce", "Dokan", "FlySend", "FlyCRM", "weDevs"]
    }

    private func save() { store.save(terms) }
}

enum TextProcessor {
    /// Deterministically normalizes known terms: fixes their casing *and* re-joins the
    /// word parts STT tends to split, e.g. "dokan" → "Dokan", "we devs" → "weDevs",
    /// "fly wp" → "FlyWP". Safe — a term only ever matches its own constituent parts,
    /// so it never touches unrelated words.
    static func canonicalize(_ text: String, terms: [String]) -> String {
        var result = text
        // Longest terms first so a shorter term can't consume part of a longer one.
        for term in terms.sorted(by: { $0.count > $1.count }) {
            let segments = parts(of: term).map { NSRegularExpression.escapedPattern(for: $0) }
            guard !segments.isEmpty else { continue }
            // Allow optional whitespace/hyphens between the term's parts.
            let pattern = "\\b" + segments.joined(separator: "[-\\s]*") + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, options: [], range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: term))
        }
        return result
    }

    /// Split a term into its word parts for spacing-tolerant matching:
    /// "weDevs" → ["we","Devs"], "FlyWP" → ["Fly","WP"], "Fly Send" → ["Fly","Send"].
    private static func parts(of term: String) -> [String] {
        var parts: [String] = []
        var current = ""
        let chars = Array(term)
        for (i, ch) in chars.enumerated() {
            if ch.isWhitespace || ch == "-" || ch == "_" {
                if !current.isEmpty { parts.append(current); current = "" }
                continue
            }
            // Start a new part before an uppercase that begins a word:
            //   lower/digit → Upper (weD, fly2C), or Upper → Upper+lower (WPFoo → WP, Foo).
            if ch.isUppercase, let prev = current.last {
                let nextLower = (i + 1 < chars.count) && chars[i + 1].isLowercase
                if prev.isLowercase || prev.isNumber || (prev.isUppercase && nextLower) {
                    parts.append(current); current = ""
                }
            }
            current.append(ch)
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    // MARK: - Fuzzy (phonetic) correction

    /// Fix terms the recognizer split or garbled phonetically, e.g. "Lara Vale" → "Laravel",
    /// which the exact `canonicalize` pass can't catch. Conservative: a 1–3 word window is
    /// replaced only when it shares the term's first letter, matches its consonant skeleton
    /// (or is a very close literal match), and is similar in length — so ordinary words are
    /// left alone.
    static func fuzzyCorrect(_ text: String, terms: [String]) -> String {
        let candidates = terms
            .map { (term: $0, key: normalize($0), skeleton: consonants($0)) }
            .filter { $0.key.count >= 4 }
        guard !candidates.isEmpty else { return text }

        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return text }

        var result = ""
        var cursor = text.startIndex
        var i = 0
        while i < tokens.count {
            var matched = false
            var size = min(3, tokens.count - i)
            while size >= 1 {
                // A multi-word window may only span soft (whitespace/hyphen) separators,
                // so we never merge across punctuation or sentence boundaries.
                if size > 1, !softlyJoined(tokens, at: i, count: size, in: text) { size -= 1; continue }
                let window = tokens[i ..< i + size].map { String(text[$0]) }.joined()
                if let term = candidates.first(where: { matches(window, key: $0.key, skeleton: $0.skeleton) })?.term {
                    result += text[cursor ..< tokens[i].lowerBound]
                    result += term
                    cursor = tokens[i + size - 1].upperBound
                    i += size
                    matched = true
                    break
                }
                size -= 1
            }
            if !matched { i += 1 }
        }
        result += text[cursor...]
        return result
    }

    private static func matches(_ window: String, key: String, skeleton: String) -> Bool {
        let a = normalize(window)
        guard a.count >= 4, a.first == key.first else { return false }
        if a == key { return true }
        let ratio = Double(min(a.count, key.count)) / Double(max(a.count, key.count))
        guard ratio >= 0.6 else { return false }
        let sim = similarity(a, key)
        if consonants(a) == skeleton, sim >= 0.65 { return true }   // phonetic match
        return sim >= 0.85                                          // near-exact literal match
    }

    /// Ranges of consecutive letter/number runs (words) in `text`.
    private static func tokenize(_ text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        var i = text.startIndex
        while i < text.endIndex {
            if text[i].isLetter || text[i].isNumber {
                if start == nil { start = i }
            } else if let s = start {
                ranges.append(s ..< i); start = nil
            }
            i = text.index(after: i)
        }
        if let s = start { ranges.append(s ..< text.endIndex) }
        return ranges
    }

    /// True if every gap between the `count` tokens starting at `at` is only whitespace/hyphens.
    private static func softlyJoined(_ tokens: [Range<String.Index>], at index: Int, count: Int, in text: String) -> Bool {
        for k in index ..< index + count - 1 {
            let gap = text[tokens[k].upperBound ..< tokens[k + 1].lowerBound]
            if gap.contains(where: { !$0.isWhitespace && $0 != "-" }) { return false }
        }
        return true
    }

    /// Lowercased, letters+digits only (spaces/punctuation stripped).
    private static func normalize(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// The normalized string with vowels removed — a cheap phonetic skeleton.
    private static func consonants(_ s: String) -> String {
        String(normalize(s).filter { !"aeiouy".contains($0) })
    }

    /// Character similarity in 0…1 (1 = identical), from Levenshtein distance.
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 1 }
        return 1 - Double(levenshtein(a, b)) / Double(maxLen)
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var prev = Array(0...t.count)
        var curr = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            curr[0] = i
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[t.count]
    }
}
