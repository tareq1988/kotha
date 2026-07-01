import SwiftUI
import Sparkle

/// Wraps Sparkle's standard updater so SwiftUI can drive "Check for Updates…".
/// Automatic checks are enabled via Info.plist (SUEnableAutomaticChecks); this
/// starts the updater and exposes a manual check for the menu.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheck = false

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheck)
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
