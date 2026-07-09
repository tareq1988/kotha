import SwiftUI

@MainActor
final class ModelManager: DownloadManager {
    static let shared = ModelManager()

    let catalog = ModelCatalog.all

    /// Model assigned to each hotkey/language.
    @Published var englishID: String { didSet { persist() } }
    @Published var banglaID: String  { didSet { persist() } }

    /// Bumped whenever an online key changes, so views recompute readiness.
    @Published private(set) var keysRevision = 0

    private var localEngines: [String: LocalSTTEngine] = [:]
    private let soniox = SonioxTranscriber()
    private let openai = OpenAITranscriber()

    override init() {
        englishID = UserDefaults.standard.string(forKey: "englishModelID") ?? "parakeet-v3"
        banglaID  = UserDefaults.standard.string(forKey: "banglaModelID")  ?? "soniox"
        super.init()
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
        case .parakeetV3:   engine = ParakeetEngine(version: .v3)
        case .parakeetV2:   engine = ParakeetEngine(version: .v2)
        case .whisperTurbo: engine = WhisperEngine()
        default:            engine = ParakeetEngine(version: .v3)
        }
        localEngines[id] = engine
        return engine
    }

    override func scanDownloaded() -> Set<String> {
        Set(ModelCatalog.downloadable.map(\.id).filter { localEngine($0).isDownloaded })
    }

    func download(_ id: String) {
        runDownload(id) { [weak self] report in
            try await self?.localEngine(id).download(progress: report)
        }
    }

    func delete(_ id: String) {
        runDelete(id) { [weak self] in
            try self?.localEngine(id).delete()
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
