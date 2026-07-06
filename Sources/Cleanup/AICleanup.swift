import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Shared prompt used by every cleanup backend (Apple + MLX).
/// Framed as strict line-in / line-out correction with few-shot examples so that
/// even very small models (e.g. Qwen 0.5B) don't treat it as an open-ended request.
enum AICleanupPrompt {
    static let instructions = """
    You are a spelling corrector for brand and product names. \
    You are given one line of TEXT and a list of KNOWN TERMS. \
    Return the exact same text, only fixing words that clearly sound like and are a \
    mis-transcription of a known term (match that term's capitalization). \
    Never replace a word that is already spelled as a known term. \
    Never swap one known term for a different one. \
    When in doubt, leave the word unchanged. \
    Do NOT answer, explain, continue, translate, or add anything. \
    Output only the corrected line of text and nothing else.
    """

    static func prompt(text: String, terms: [String]) -> String {
        """
        Known terms: FlyCommerce, Dokan, weDevs
        Text: we devs has a lot of products
        Corrected: weDevs has a lot of products

        Known terms: Laravel, FlyCommerce
        Text: laravel is awesome
        Corrected: Laravel is awesome

        Known terms: Laravel, Dokan
        Text: i use laravel and doc on every day
        Corrected: i use Laravel and Dokan every day

        Known terms: \(terms.joined(separator: ", "))
        Text: \(text)
        Corrected:
        """
    }

    /// Strip a leading "Corrected:" the model may echo, and take just the first line.
    static func clean(_ output: String, fallback: String) -> String {
        var s = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = s.range(of: "Corrected:", options: [.caseInsensitive, .anchored]) {
            s = String(s[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        s = s.split(separator: "\n").first.map(String.init) ?? s
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? fallback : s
    }

    /// Reject implausible cleanups (small models sometimes ramble) → caller falls back.
    static func isPlausible(original: String, candidate: String) -> Bool {
        let c = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return false }
        if c.count > original.count * 2 + 40 { return false }
        return true
    }

    /// Guard against over-correction. Small models sometimes swap a *correct* known
    /// term for a different one (e.g. "Laravel is awesome" → "FlyCommerce is awesome").
    /// If the candidate introduces a known term that isn't a plausible mis-transcription
    /// of what was actually said, reject the whole candidate so the caller falls back.
    static func verify(original: String, candidate: String, terms: [String]) -> String {
        let termSet = Set(terms.map { $0.lowercased() })
        let originalWords = words(original)
        let removed = multisetDifference(words(original), from: candidate.isEmpty ? [] : words(candidate))
        let added = multisetDifference(words(candidate), from: originalWords)
        for word in added where termSet.contains(word) {
            if !isMishear(of: word, from: removed) { return original }
        }
        return candidate
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Elements of `a` not covered by `b`, respecting multiplicity.
    private static func multisetDifference(_ a: [String], from b: [String]) -> [String] {
        var counts: [String: Int] = [:]
        for w in b { counts[w, default: 0] += 1 }
        return a.filter { w in
            if let n = counts[w], n > 0 { counts[w] = n - 1; return false }
            return true
        }
    }

    /// True if `term` looks like a mis-transcription of one or more of the `removed` words,
    /// e.g. "dokan" ~ "doc"+"on" ("docon"). Rejects unrelated swaps like "flycommerce" vs "laravel".
    private static func isMishear(of term: String, from removed: [String]) -> Bool {
        guard !removed.isEmpty else { return false }
        var sources = removed
        sources.append(removed.joined())          // the split-word case: ["doc","on"] → "docon"
        return sources.contains { TextProcessor.similarity(term, $0) >= 0.5 }
    }
}

/// On-device transcript cleanup using Apple's Foundation Models (macOS 26+).
/// Fixes mis-transcribed known terms without changing anything else.
enum AICleanup {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static func correct(_ text: String, terms: [String]) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return text }

            let session = LanguageModelSession(instructions: AICleanupPrompt.instructions)
            let response = try await session.respond(
                to: AICleanupPrompt.prompt(text: text, terms: terms),
                options: GenerationOptions(temperature: 0))
            return AICleanupPrompt.clean(response.content, fallback: text)
        }
        #endif
        return text
    }
}
