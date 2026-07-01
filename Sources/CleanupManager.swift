import SwiftUI

struct CleanupModelInfo: Identifiable {
    let id: String
    let name: String
    let detail: String
    let size: String            // "Built-in" for the OS model, otherwise download size
    let provider: Provider

    enum Provider: Equatable {
        case apple
        case mlx(repo: String)
    }

    var isLocal: Bool { if case .mlx = provider { return true } else { return false } }
}

@MainActor
final class CleanupManager: ObservableObject {
    static let shared = CleanupManager()

    let catalog: [CleanupModelInfo] = [
        CleanupModelInfo(
            id: "apple", name: "Apple on-device",
            detail: "Built into macOS, runs on the Neural Engine. Fast & private.",
            size: "Built-in", provider: .apple),
        CleanupModelInfo(
            id: "qwen2.5-0.5b", name: "Qwen2.5 0.5B",
            detail: "Smallest & fastest downloadable model (4-bit).",
            size: "≈300 MB", provider: .mlx(repo: "mlx-community/Qwen2.5-0.5B-Instruct-4bit")),
        CleanupModelInfo(
            id: "llama3.2-1b", name: "Llama 3.2 1B",
            detail: "A bit larger, stronger (4-bit).",
            size: "≈700 MB", provider: .mlx(repo: "mlx-community/Llama-3.2-1B-Instruct-4bit")),
        CleanupModelInfo(
            id: "gemma2-2b", name: "Gemma 2 2B",
            detail: "Largest of the small set, most capable (4-bit).",
            size: "≈1.4 GB", provider: .mlx(repo: "mlx-community/gemma-2-2b-it-4bit")),
    ]

    @Published var selectedID: String { didSet { UserDefaults.standard.set(selectedID, forKey: "cleanupModelID") } }
    @Published private(set) var downloadedIDs: Set<String> = []
    @Published private(set) var busyID: String?
    @Published private(set) var progress: [String: Double] = [:]

    private var engines: [String: MLXCleanupEngine] = [:]

    init() {
        selectedID = UserDefaults.standard.string(forKey: "cleanupModelID") ?? "apple"
        refresh()
    }

    private func engine(for info: CleanupModelInfo) -> MLXCleanupEngine? {
        guard case .mlx(let repo) = info.provider else { return nil }
        if let e = engines[info.id] { return e }
        let e = MLXCleanupEngine(repo: repo)
        engines[info.id] = e
        return e
    }

    func info(_ id: String) -> CleanupModelInfo? { catalog.first { $0.id == id } }
    var selectedInfo: CleanupModelInfo { info(selectedID) ?? catalog[0] }

    func refresh() {
        downloadedIDs = Set(catalog.filter { info in
            if case .mlx = info.provider { return engine(for: info)?.isDownloaded == true }
            return false
        }.map(\.id))
    }

    func isDownloaded(_ id: String) -> Bool { downloadedIDs.contains(id) }

    func isReady(_ info: CleanupModelInfo) -> Bool {
        switch info.provider {
        case .apple:  return AICleanup.isAvailable
        case .mlx:    return isDownloaded(info.id)
        }
    }

    var selectedIsReady: Bool { isReady(selectedInfo) }

    func download(_ id: String) {
        guard busyID == nil, let info = info(id), let engine = engine(for: info) else { return }
        busyID = id
        progress[id] = 0
        Task {
            do {
                try await engine.download { [weak self] fraction in
                    Task { @MainActor in self?.progress[id] = fraction }
                }
            } catch {
                NSLog("Kotha: MLX download \(id) failed: \(error.localizedDescription)")
            }
            progress[id] = nil
            busyID = nil
            refresh()
        }
    }

    func delete(_ id: String) {
        guard busyID == nil, let info = info(id), let engine = engine(for: info) else { return }
        busyID = id
        Task {
            try? engine.delete()
            busyID = nil
            refresh()
        }
    }

    func correct(_ text: String, terms: [String]) async throws -> String {
        let info = selectedInfo
        switch info.provider {
        case .apple:
            return try await AICleanup.correct(text, terms: terms)
        case .mlx:
            guard let engine = engine(for: info) else { return text }
            return try await engine.correct(text, terms: terms)
        }
    }
}
