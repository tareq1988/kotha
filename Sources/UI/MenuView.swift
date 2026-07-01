import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var models: ModelManager
    @ObservedObject private var updater = Updater.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(app.statusText)

        if !app.lastText.isEmpty {
            Text("Last: \(String(app.lastText.prefix(50)))")
                .font(.caption)
        }

        Divider()

        Text("\(HotkeyConfig.key(for: .english).label) → \(models.name(for: .english))")
        Text("\(HotkeyConfig.key(for: .bangla).label) → \(models.name(for: .bangla))")

        Divider()

        Button("Overview…") { open(.overview) }
        Button("History…")  { open(.history) }
        Button("Settings…") { open(.settings) }
            .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheck)

        Button("Quit Kotha") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func open(_ section: AppSection) {
        UserDefaults.standard.set(section.rawValue, forKey: "mainSection")
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}
