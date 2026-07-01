import SwiftUI

/// Shared download / delete / progress bookkeeping for the model managers.
/// Subclasses supply *what* is downloaded and *how* each action runs; this base
/// owns the published state (busy id, per-id progress, the downloaded set).
@MainActor
class DownloadManager: ObservableObject {
    @Published private(set) var downloadedIDs: Set<String> = []
    @Published private(set) var busyID: String?
    @Published private(set) var progress: [String: Double] = [:]

    func isDownloaded(_ id: String) -> Bool { downloadedIDs.contains(id) }

    /// Which ids are currently present on disk. Override in subclasses.
    func scanDownloaded() -> Set<String> { [] }

    func refresh() { downloadedIDs = scanDownloaded() }

    /// Download `id`, reporting progress and refreshing when done. One at a time.
    func runDownload(_ id: String,
                     _ action: @escaping (_ report: @escaping (Double) -> Void) async throws -> Void) {
        guard busyID == nil else { return }
        busyID = id
        progress[id] = 0
        Task {
            do {
                try await action { [weak self] fraction in
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

    func runDelete(_ id: String, _ action: @escaping () async throws -> Void) {
        guard busyID == nil else { return }
        busyID = id
        Task {
            try? await action()
            busyID = nil
            refresh()
        }
    }
}
