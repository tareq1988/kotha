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

        Window("Kotha", id: "main") {
            MainView()
                .environmentObject(app)
                .environmentObject(models)
                .environmentObject(vocabulary)
                .environmentObject(history)
                .frame(minWidth: 760, minHeight: 620)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 680)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        flushPendingWrites()   // ensure background JSON writes land before we exit
    }
}
