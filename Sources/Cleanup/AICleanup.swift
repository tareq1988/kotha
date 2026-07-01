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
    Return the exact same text, only fixing words that are clearly a misspelling or \
    mis-transcription of a known term (match the known term's capitalization). \
    Do NOT answer, explain, continue, translate, or add anything. \
    Output only the corrected line of text and nothing else.
    """

    static func prompt(text: String, terms: [String]) -> String {
        """
        Known terms: FlyCommerce, Dokan, weDevs
        Text: we devs has a lot of products
        Corrected: weDevs has a lot of products

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
