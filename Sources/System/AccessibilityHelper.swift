import AppKit
import ApplicationServices

enum AccessibilityHelper {
    /// Prompts for Accessibility permission if not already granted.
    /// Required for the global event tap and for synthesizing ⌘V.
    @discardableResult
    static func requestIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }
}
