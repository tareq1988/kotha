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

    /// key code → language. Updated live when the user reconfigures hotkeys.
    private var mapping: [Int64: Language]

    init(mapping: [Int64: Language],
         onPress: @escaping (Language) -> Void,
         onRelease: @escaping (Language) -> Void) {
        self.mapping = mapping
        self.onPress = onPress
        self.onRelease = onRelease
    }

    /// Replace the trigger keys. Runs on the main thread (same as the tap callback).
    func updateMapping(_ mapping: [Int64: Language]) {
        self.mapping = mapping
        pressed.removeAll()
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
        guard let lang = mapping[keyCode] else { return }

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
