import SwiftUI

@MainActor
final class ModelManager: ObservableObject {
    static let shared = ModelManager()

    let catalog = ModelCatalog.all

    /// Model assigned to each hotkey/language.
    @Published var englishID: String { didSet { persist() } }
    @Published var banglaID: String  { didSet { persist() } }

    @Published private(set) var downloadedIDs: Set<String> = []
    @Published private(set) var busyID: String?          // local model downloading/deleting
    @Published private(set) var progress: [String: Double] = [:]   // id → 0...1 while downloading
    /// Bumped whenever an online key changes, so views recompute readiness.
    @Published private(set) var keysRevision = 0

    private var localEngines: [String: LocalSTTEngine] = [:]
    private let soniox = SonioxTranscriber()
    private let openai = OpenAITranscriber()

    init() {
        englishID = UserDefaults.standard.string(forKey: "englishModelID") ?? "parakeet-v3"
        banglaID  = UserDefaults.standard.string(forKey: "banglaModelID")  ?? "soniox"
        refresh()
    }

    private func persist() {
        UserDefaults.standard.set(englishID, forKey: "englishModelID")
        UserDefaults.standard.set(banglaID, forKey: "banglaModelID")
    }

    func assignedID(for language: Language) -> String {
        language == .bangla ? banglaID : englishID
    }

    func setModel(_ id: String, for language: Language) {
        if language == .bangla { banglaID = id } else { englishID = id }
        if let info = ModelCatalog.info(id), info.provider == .local, isDownloaded(id) {
            Task { try? await localEngine(id).load() }
        }
    }

    // MARK: - Local model lifecycle

    private func localEngine(_ id: String) -> LocalSTTEngine {
        if let engine = localEngines[id] { return engine }
        let info = ModelCatalog.info(id) ?? catalog[0]
        let engine: LocalSTTEngine
        switch info.kind {
        case .parakeetV3:   engine = ParakeetEngine(version: .v3, folderName: "parakeet-tdt-0.6b-v3")
        case .parakeetV2:   engine = ParakeetEngine(version: .v2, folderName: "parakeet-tdt-0.6b-v2")
        case .whisperTurbo: engine = WhisperEngine()
        default:            engine = ParakeetEngine(version: .v3, folderName: "parakeet-tdt-0.6b-v3")
        }
        localEngines[id] = engine
        return engine
    }

    func refresh() {
        downloadedIDs = Set(ModelCatalog.downloadable.map(\.id).filter { localEngine($0).isDownloaded })
    }

    func isDownloaded(_ id: String) -> Bool { downloadedIDs.contains(id) }

    func download(_ id: String) {
        guard busyID == nil else { return }
        busyID = id
        progress[id] = 0
        Task {
            do {
                try await localEngine(id).download { [weak self] fraction in
                    Task { @MainActor in self?.progress[id] = fraction }
                }
            } catch {
                NSLog("Kotha: download \(id) failed: \(error.localizedDescription)")
            }
            progress[id] = nil
            busyID = nil
            refresh()
        }
    }

    func delete(_ id: String) {
        guard busyID == nil else { return }
        busyID = id
        Task {
            try? localEngine(id).delete()
            busyID = nil
            refresh()
        }
    }

    // MARK: - Online keys

    func hasKey(_ info: ModelInfo) -> Bool {
        guard let account = info.kind.keyAccount else { return true }
        return SecretStore.shared.hasKey(for: account)
    }

    func saveKey(_ value: String, for info: ModelInfo) {
        guard let account = info.kind.keyAccount else { return }
        SecretStore.shared.setKey(value, for: account)
        keysRevision += 1
    }

    func key(for info: ModelInfo) -> String {
        guard let account = info.kind.keyAccount else { return "" }
        return SecretStore.shared.key(for: account) ?? ""
    }

    // MARK: - Readiness & display

    func ready(_ info: ModelInfo) -> Bool {
        switch info.kind {
        case .appleSpeech: return AppleSpeechEngine.authorized
        case .soniox, .openai: return hasKey(info)
        default: return isDownloaded(info.id)
        }
    }

    /// Language-aware readiness (Apple's on-device model is per-locale).
    func ready(_ info: ModelInfo, for language: Language) -> Bool {
        if info.kind == .appleSpeech { return AppleSpeechEngine.shared.isReady(for: language) }
        return ready(info)
    }

    func ready(for language: Language) -> Bool {
        guard let info = ModelCatalog.info(assignedID(for: language)) else { return false }
        return ready(info, for: language)
    }

    func name(for language: Language) -> String {
        ModelCatalog.info(assignedID(for: language))?.name ?? "—"
    }

    // MARK: - Startup preload & transcription

    func preloadAssigned() async {
        let id = englishID
        guard let info = ModelCatalog.info(id), info.provider == .local, isDownloaded(id) else { return }
        try? await localEngine(id).load()
    }

    func transcribe(_ samples: [Float], language: Language) async throws -> String {
        let id = assignedID(for: language)
        guard let info = ModelCatalog.info(id) else { return "" }
        switch info.kind {
        case .parakeetV3, .parakeetV2, .whisperTurbo:
            return try await localEngine(id).transcribe(samples)
        case .appleSpeech:
            return try await AppleSpeechEngine.shared.transcribe(samples, language: language)
        case .soniox:
            return try await soniox.transcribe(samples: samples, sampleRate: 16_000, language: language)
        case .openai:
            return try await openai.transcribe(samples: samples, sampleRate: 16_000, language: language)
        }
    }
}
