import SwiftUI
import AppKit

@main
struct KothaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState.shared
    @StateObject private var models = ModelManager.shared
    @StateObject private var vocabulary = VocabularyStore.shared
    @StateObject private var history = HistoryStore.shared

    var body: some Scene {
        MenuBarExtra("Kotha", systemImage: app.menuIcon) {
            MenuView().environmentObject(app).environmentObject(models)
        }

        Settings {
            SettingsView()
                .environmentObject(app)
                .environmentObject(models)
                .environmentObject(vocabulary)
        }

        Window("Kotha — History", id: "history") {
            HistoryView().environmentObject(history)
        }
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.start()
    }
}
