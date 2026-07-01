import Foundation

/// A single modifier key usable as a press-and-hold dictation trigger.
/// (Modifier keys only — you can hold them without typing anything.)
enum ModifierKey: String, CaseIterable, Identifiable {
    case rightCommand, leftCommand
    case rightOption, leftOption
    case rightControl, leftControl
    case rightShift, leftShift
    case function

    var id: String { rawValue }

    /// macOS virtual key code reported by `flagsChanged`.
    var keyCode: Int64 {
        switch self {
        case .rightCommand: return 54
        case .leftCommand:  return 55
        case .rightOption:  return 61
        case .leftOption:   return 58
        case .rightControl: return 62
        case .leftControl:  return 59
        case .rightShift:   return 60
        case .leftShift:    return 56
        case .function:     return 63
        }
    }

    var label: String {
        switch self {
        case .rightCommand: return "Right ⌘"
        case .leftCommand:  return "Left ⌘"
        case .rightOption:  return "Right ⌥"
        case .leftOption:   return "Left ⌥"
        case .rightControl: return "Right ⌃"
        case .leftControl:  return "Left ⌃"
        case .rightShift:   return "Right ⇧"
        case .leftShift:    return "Left ⇧"
        case .function:     return "Fn 🌐"
        }
    }
}

/// Persisted per-language trigger keys. The two languages are kept distinct:
/// assigning a key already used by the other language swaps them.
enum HotkeyConfig {
    private static func defaultsKey(_ lang: Language) -> String { "hotkey.\(lang.rawValue)" }

    private static func fallback(_ lang: Language) -> ModifierKey {
        lang == .english ? .rightCommand : .rightOption
    }

    static func key(for lang: Language) -> ModifierKey {
        let raw = UserDefaults.standard.string(forKey: defaultsKey(lang))
        return ModifierKey(rawValue: raw ?? "") ?? fallback(lang)
    }

    static func setKey(_ newKey: ModifierKey, for lang: Language) {
        let other: Language = (lang == .english) ? .bangla : .english
        let oldKey = key(for: lang)
        if key(for: other) == newKey {
            UserDefaults.standard.set(oldKey.rawValue, forKey: defaultsKey(other))
        }
        UserDefaults.standard.set(newKey.rawValue, forKey: defaultsKey(lang))
    }

    /// key code → language, for the event monitor.
    static var mapping: [Int64: Language] {
        [key(for: .english).keyCode: .english,
         key(for: .bangla).keyCode: .bangla]
    }
}
