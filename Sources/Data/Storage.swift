import Foundation

enum AppPaths {
    /// ~/Library/Application Support/Kotha (created once, on first use).
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Kotha", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}

/// Serial queue backing every JSONStore write, so disk I/O never blocks the main thread.
private let jsonStoreQueue = DispatchQueue(label: "com.tareq.kotha.jsonstore")

/// Block until all pending JSONStore writes have flushed. Call on app termination.
func flushPendingWrites() { jsonStoreQueue.sync {} }

/// Persists a Codable value as JSON in Application Support.
/// Loads are synchronous; saves are encoded and written on a background serial queue,
/// so callers (whose in-memory state is the source of truth) never wait on disk.
final class JSONStore<Value: Codable> {
    private let url: URL
    private let ownerOnly: Bool

    /// - Parameter ownerOnly: restrict the file to `0600` (used for secrets).
    init(_ filename: String, ownerOnly: Bool = false) {
        self.url = AppPaths.support.appendingPathComponent(filename)
        self.ownerOnly = ownerOnly
    }

    func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        let url = self.url
        let ownerOnly = self.ownerOnly
        jsonStoreQueue.async {
            guard let data = try? JSONEncoder().encode(value) else { return }
            try? data.write(to: url, options: .atomic)
            if ownerOnly {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
        }
    }
}
