import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var models: ModelManager
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(app.statusText)

        if !app.lastText.isEmpty {
            Text("Last: \(String(app.lastText.prefix(50)))")
                .font(.caption)
        }

        Divider()

        Text("Right ⌘ → \(models.name(for: .english))")
        Text("Right ⌥ → \(models.name(for: .bangla))")

        Divider()

        Button("History…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "history")
        }

        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Quit Kotha") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
