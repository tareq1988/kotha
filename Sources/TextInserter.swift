import AppKit

/// Inserts text into the focused app by placing it on the pasteboard and
/// synthesizing ⌘V, then restoring the previous pasteboard contents.
final class TextInserter {
    /// Insert `text` into the focused app via paste.
    /// - Parameter keepOnClipboard: when true, leave the dictated text on the
    ///   clipboard afterwards instead of restoring the previous contents.
    func insert(_ text: String, keepOnClipboard: Bool = false) {
        let pasteboard = NSPasteboard.general
        let saved = keepOnClipboard ? [] : snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        paste()

        guard !keepOnClipboard else { return }

        // Restore the user's clipboard once the paste has landed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            pasteboard.clearContents()
            if !saved.isEmpty {
                pasteboard.writeObjects(saved)
            }
        }
    }

    private func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private func paste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9   // "V"

        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
