import Foundation
import FluidAudio
import WhisperKit

// MARK: - Catalog

enum ModelProvider { case local, online }

enum ModelEngineKind {
    case parakeetV3, parakeetV2, whisperTurbo   // local (downloadable)
    case appleSpeech                             // local (built-in)
    case soniox, openai                          // online

    /// Keychain account for online providers.
    var keyAccount: String? {
        switch self {
        case .soniox: return "soniox"
        case .openai: return "openai"
        default: return nil
        }
    }
}

struct ModelInfo: Identifiable {
    let id: String
    let name: String
    let detail: String
    let provider: ModelProvider
    let kind: ModelEngineKind
    let size: String?            // local download size; nil for online
    let supportsBangla: Bool     // English is supported by all
}

enum ModelCatalog {
    static let all: [ModelInfo] = [
        ModelInfo(id: "apple-speech", name: "Apple on-device",
                  detail: "Built into macOS, no download, private.",
                  provider: .local, kind: .appleSpeech, size: "Built-in", supportsBangla: true),
        ModelInfo(id: "parakeet-v3", name: "NVIDIA Parakeet TDT 0.6B v3",
                  detail: "Ultra-fast, on-device. Recommended for English.",
                  provider: .local, kind: .parakeetV3, size: "496 MB", supportsBangla: false),
        ModelInfo(id: "parakeet-v2", name: "NVIDIA Parakeet TDT 0.6B v2",
                  detail: "On-device, English-only, higher recall.",
                  provider: .local, kind: .parakeetV2, size: "496 MB", supportsBangla: false),
        ModelInfo(id: "whisper-large-v3-turbo", name: "Whisper Large v3 Turbo",
                  detail: "On-device, multilingual, higher accuracy.",
                  provider: .local, kind: .whisperTurbo, size: "~1.5 GB", supportsBangla: true),
        ModelInfo(id: "soniox", name: "Soniox",
                  detail: "Online, fast & accurate for Bangla.",
                  provider: .online, kind: .soniox, size: nil, supportsBangla: true),
        ModelInfo(id: "openai", name: "OpenAI gpt-4o-transcribe",
                  detail: "Online, multilingual.",
                  provider: .online, kind: .openai, size: nil, supportsBangla: true),
    ]

    static func info(_ id: String) -> ModelInfo? { all.first { $0.id == id } }

    static var local: [ModelInfo]   { all.filter { $0.provider == .local } }
    static var online: [ModelInfo]  { all.filter { $0.provider == .online } }
    /// Local models that download from HuggingFace (excludes the built-in Apple model).
    static var downloadable: [ModelInfo] { all.filter { $0.provider == .local && $0.kind != .appleSpeech } }
    /// Every model handles English; only some handle Bangla.
    static func forLanguage(_ language: Language) -> [ModelInfo] {
        language == .bangla ? all.filter(\.supportsBangla) : all
    }
}

// MARK: - Storage

enum ModelStorage {
    /// Kotha-owned models directory: ~/Library/Application Support/Kotha/Models
    static let root: URL = {
        let dir = AppPaths.support.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}

// MARK: - Engine abstraction

protocol LocalSTTEngine: AnyObject {
    var isDownloaded: Bool { get }
    func download(progress: @escaping (Double) -> Void) async throws
    func load() async throws
    func transcribe(_ samples: [Float]) async throws -> String
    func delete() throws
}

// MARK: - Parakeet (FluidAudio)

final class ParakeetEngine: LocalSTTEngine {
    private let version: AsrModelVersion
    private let folderName: String          // on-disk repo folder, for deletion
    private var manager: AsrManager?

    /// Shared parent passed to FluidAudio; it places each version in its own repo subfolder.
    private var slot: URL { ModelStorage.root.appendingPathComponent("parakeet") }
    private var modelDir: URL { ModelStorage.root.appendingPathComponent(folderName) }

    init(version: AsrModelVersion, folderName: String) {
        self.version = version
        self.folderName = folderName
    }

    var isDownloaded: Bool { AsrModels.modelsExist(at: slot, version: version) }

    func download(progress: @escaping (Double) -> Void) async throws {
        _ = try await AsrModels.download(to: slot, version: version) { p in
            progress(p.fractionCompleted)
        }
    }

    func load() async throws {
        guard manager == nil else { return }
        let models = try await AsrModels.downloadAndLoad(to: slot, version: version)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        if manager == nil { try await load() }
        guard let manager else { return "" }
        var decoderState = try TdtDecoderState()
        return try await manager.transcribe(samples, decoderState: &decoderState).text
    }

    func delete() throws {
        manager = nil
        if FileManager.default.fileExists(atPath: modelDir.path) {
            try FileManager.default.removeItem(at: modelDir)
        }
    }
}

// MARK: - Whisper (WhisperKit)

final class WhisperEngine: LocalSTTEngine {
    private let variant = "large-v3-v20240930_turbo"
    private let folderKey = "whisper.large-v3-turbo.folder"
    private var kit: WhisperKit?

    private var downloadBase: URL { ModelStorage.root.appendingPathComponent("whisper") }

    private var storedFolder: URL? {
        guard let path = UserDefaults.standard.string(forKey: folderKey) else { return nil }
        return URL(fileURLWithPath: path)
    }

    var isDownloaded: Bool {
        guard let folder = storedFolder else { return false }
        return FileManager.default.fileExists(atPath: folder.path)
    }

    func download(progress: @escaping (Double) -> Void) async throws {
        let url = try await WhisperKit.download(variant: variant, downloadBase: downloadBase) { p in
            progress(p.fractionCompleted)
        }
        UserDefaults.standard.set(url.path, forKey: folderKey)
    }

    func load() async throws {
        guard kit == nil else { return }
        if !isDownloaded { try await download { _ in } }
        let config = WhisperKitConfig(
            model: variant,
            modelFolder: storedFolder?.path,
            load: true,
            download: false
        )
        kit = try await WhisperKit(config)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        if kit == nil { try await load() }
        guard let kit else { return "" }
        let results = try await kit.transcribe(audioArray: samples)
        return results.map(\.text).joined(separator: " ")
    }

    func delete() throws {
        kit = nil
        if let folder = storedFolder, FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        UserDefaults.standard.removeObject(forKey: folderKey)
    }
}
