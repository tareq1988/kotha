import Foundation
import Hub
import MLXLLM
import MLXLMCommon

/// Runs a small quantized LLM (Qwen / Llama / Gemma) locally via MLX for vocabulary cleanup.
@MainActor
final class MLXCleanupEngine {
    let repo: String                     // e.g. "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
    private var container: ModelContainer?

    init(repo: String) { self.repo = repo }

    private var base: URL { ModelStorage.root.appendingPathComponent("mlx", isDirectory: true) }
    private var hub: HubApi { HubApi(downloadBase: base) }
    private var modelDir: URL { base.appendingPathComponent("models/\(repo)", isDirectory: true) }

    var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: modelDir.appendingPathComponent("config.json").path)
    }

    func download(progress: @escaping (Double) -> Void) async throws {
        container = try await loadModelContainer(hub: hub, id: repo) { p in
            progress(p.fractionCompleted)
        }
    }

    func load() async throws {
        guard container == nil else { return }
        container = try await loadModelContainer(hub: hub, id: repo)
    }

    func correct(_ text: String, terms: [String]) async throws -> String {
        try await load()
        guard let container else { return text }

        // Bound output to roughly the input length so a weak model can't ramble.
        let wordCount = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
        let maxTokens = min(220, max(24, wordCount * 2 + 24))

        let session = ChatSession(
            container,
            instructions: AICleanupPrompt.instructions,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0))
        let out = try await session.respond(to: AICleanupPrompt.prompt(text: text, terms: terms))
        return AICleanupPrompt.clean(out, fallback: text)
    }

    func delete() throws {
        container = nil
        if FileManager.default.fileExists(atPath: modelDir.path) {
            try FileManager.default.removeItem(at: modelDir)
        }
    }
}
