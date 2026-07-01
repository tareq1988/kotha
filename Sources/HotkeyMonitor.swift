import AppKit
import CoreGraphics

/// Watches global modifier-key changes and reports press / release of the
/// right Command and right Option keys (used as press-and-hold dictation triggers).
final class HotkeyMonitor {
    private let onPress: (Language) -> Void
    private let onRelease: (Language) -> Void

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pressed = Set<Int64>()

    // macOS virtual key codes for the right-side modifiers.
    private let rightCommand: Int64 = 54
    private let rightOption: Int64 = 61

    init(onPress: @escaping (Language) -> Void,
         onRelease: @escaping (Language) -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
    }

    func start() {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, refcon in
                if let refcon {
                    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                    monitor.handle(event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            NSLog("Kotha: could not create event tap — grant Accessibility permission.")
            return
        }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == rightCommand || keyCode == rightOption else { return }

        let lang: Language = (keyCode == rightCommand) ? .english : .bangla

        // Each flagsChanged for a modifier toggles its physical state.
        let isDown: Bool
        if pressed.contains(keyCode) {
            pressed.remove(keyCode)
            isDown = false
        } else {
            pressed.insert(keyCode)
            isDown = true
        }

        DispatchQueue.main.async { [onPress, onRelease] in
            if isDown { onPress(lang) } else { onRelease(lang) }
        }
    }
}
