import SwiftUI
import AppKit

/// Shows a Dock icon while the main window is open and hides it when the window
/// closes — without ever touching the menu-bar item. Drop `WindowAccessor()` into
/// the window's content background.
struct WindowAccessor: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator: NSObject {
        private var window: NSWindow?

        func attach(to window: NSWindow) {
            guard self.window == nil else { return }
            self.window = window
            DockPolicy.showDock()
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification, object: window)
        }

        @objc private func windowWillClose(_ note: Notification) {
            DockPolicy.hideDock()
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

enum DockPolicy {
    static func showDock() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func hideDock() {
        // Back to menu-bar-only. The MenuBarExtra item is unaffected.
        NSApp.setActivationPolicy(.accessory)
    }
}
