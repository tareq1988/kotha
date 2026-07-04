import SwiftUI
import AppKit

enum Language: String {
    case english
    case bangla

    var display: String { self == .english ? "EN" : "বাং" }
    var label: String { self == .english ? "English" : "Bangla" }
}

enum ActivationMode: String, CaseIterable, Identifiable {
    case hold
    case toggle
    case doubleTap
    case holdOrToggle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hold:         return "Hold to talk"
        case .toggle:       return "Toggle (tap on / tap off)"
        case .doubleTap:    return "Double-tap to toggle"
        case .holdOrToggle: return "Hold or tap"
        }
    }

    var help: String {
        switch self {
        case .hold:         return "Hold the key while speaking; release to insert."
        case .toggle:       return "Tap once to start, tap again to stop & insert."
        case .doubleTap:    return "Double-tap to start, double-tap to stop & insert."
        case .holdOrToggle: return "Hold to talk, or a quick tap to keep it on."
        }
    }

    static var current: ActivationMode {
        ActivationMode(rawValue: UserDefaults.standard.string(forKey: "activationMode") ?? "") ?? .hold
    }
}

/// Which languages vocabulary cleanup applies to.
enum CleanupScope: String, CaseIterable, Identifiable {
    case both
    case english
    case bangla

    var id: String { rawValue }

    var label: String {
        switch self {
        case .both:    return "English & Bangla"
        case .english: return "English only"
        case .bangla:  return "Bangla only"
        }
    }

    func applies(to lang: Language) -> Bool {
        switch self {
        case .both:    return true
        case .english: return lang == .english
        case .bangla:  return lang == .bangla
        }
    }

    static var current: CleanupScope {
        CleanupScope(rawValue: UserDefaults.standard.string(forKey: "cleanupLanguage") ?? "") ?? .both
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Status: Equatable {
        case idle
        case loadingModel
        case recording(Language)
        case transcribing(Language)
        case refining(Language)
        case success(Language)
        case error(String)
    }

    @Published var status: Status = .idle
    @Published var modelReady = false
    @Published var lastText = ""
    @Published var micLevel: Float = 0

    private let recorder = AudioRecorder()
    let models = ModelManager.shared
    private let inserter = TextInserter()
    private var hotkeys: HotkeyMonitor?
    private var activeLanguage: Language?
    private var transcriptionTask: Task<Void, Never>?

    // Activation-mode bookkeeping
    private var pressTime: [Language: TimeInterval] = [:]
    private var lastTap: [Language: TimeInterval] = [:]
    private var toggledOn: Language?
    private let tapWindow: TimeInterval = 0.35
    private let holdThreshold: TimeInterval = 0.35

    var menuIcon: String {
        switch status {
        case .recording:                 return "waveform.circle.fill"
        case .transcribing, .loadingModel: return "ellipsis.circle"
        case .refining:                  return "sparkles"
        case .success:                   return "checkmark.circle"
        case .error:                     return "exclamationmark.triangle"
        case .idle:                      return "waveform"
        }
    }

    var isBusy: Bool {
        switch status {
        case .idle, .success, .error: return false
        default:                      return true
        }
    }

    var statusText: String {
        switch status {
        case .idle:                  return models.ready(for: .english) ? "Ready" : "Set up English model — open Settings"
        case .loadingModel:          return "Downloading English model…"
        case .recording(let l):      return "Listening · \(l.label)"
        case .transcribing(let l):   return "Transcribing · \(l.label)"
        case .refining(let l):       return "Refining · \(l.label)"
        case .success:               return "Inserted"
        case .error(let m):          return "Error: \(m)"
        }
    }

    func start() {
        AccessibilityHelper.requestIfNeeded()

        recorder.onLevel = { [weak self] level in
            Task { @MainActor in self?.micLevel = level }
        }

        hotkeys = HotkeyMonitor(
            mapping:   HotkeyConfig.mapping,
            onPress:   { [weak self] lang in self?.handlePress(lang) },
            onRelease: { [weak self] lang in self?.handleRelease(lang) }
        )
        hotkeys?.start()

        ListeningPanel.shared.start()
        Task { await loadModel() }
    }

    /// Re-read the configured trigger keys (call after the user changes them).
    func reloadHotkeys() {
        hotkeys?.updateMapping(HotkeyConfig.mapping)
    }

    private func loadModel() async {
        guard !modelReady else { return }
        guard models.ready(for: .english) else {
            // English model not set up yet — prompt the user via Settings.
            status = .idle
            return
        }
        status = .loadingModel
        await models.preloadAssigned()
        modelReady = true
        status = .idle
    }

    // MARK: - Activation handling

    private func isRecording(_ lang: Language) -> Bool { activeLanguage == lang }

    private func handlePress(_ lang: Language) {
        let now = ProcessInfo.processInfo.systemUptime
        switch ActivationMode.current {
        case .hold:
            startRecording(lang)

        case .toggle:
            if isRecording(lang) { stopAndTranscribe(lang) } else { startRecording(lang) }

        case .doubleTap:
            if now - (lastTap[lang] ?? 0) < tapWindow {
                lastTap[lang] = 0
                if isRecording(lang) { stopAndTranscribe(lang) } else { startRecording(lang) }
            } else {
                lastTap[lang] = now
            }

        case .holdOrToggle:
            if toggledOn == lang {           // already latched on → this press stops it
                stopAndTranscribe(lang)
            } else {
                pressTime[lang] = now
                startRecording(lang)
            }
        }
    }

    private func handleRelease(_ lang: Language) {
        switch ActivationMode.current {
        case .hold:
            if isRecording(lang) { stopAndTranscribe(lang) }

        case .holdOrToggle:
            guard isRecording(lang), toggledOn == nil else { return }
            let held = ProcessInfo.processInfo.systemUptime - (pressTime[lang] ?? 0)
            if held >= holdThreshold {
                stopAndTranscribe(lang)      // was a real hold
            } else {
                toggledOn = lang             // quick tap → stay recording until next press
            }

        case .toggle, .doubleTap:
            break                            // release is irrelevant in these modes
        }
    }

    // MARK: - Recording lifecycle

    private func startRecording(_ lang: Language) {
        guard activeLanguage == nil else { return }       // one session at a time
        activeLanguage = lang
        status = .recording(lang)
        do {
            try recorder.start()
            if UserDefaults.standard.bool(forKey: "muteWhileDictating") {
                SystemAudio.muteOutput()
            }
        } catch {
            activeLanguage = nil
            setError("Mic: \(error.localizedDescription)")
        }
    }

    private func stopAndTranscribe(_ lang: Language) {
        guard activeLanguage == lang else { return }
        activeLanguage = nil
        toggledOn = nil
        let samples = recorder.stop()
        SystemAudio.restoreOutput()
        micLevel = 0

        // Ignore taps shorter than ~0.15s
        guard samples.count > 2400 else {
            status = .idle
            return
        }

        status = .transcribing(lang)
        transcriptionTask = Task { await transcribeAndInsert(lang, samples: samples) }
    }

    /// Cancel an in-progress recording or transcription and reset to idle.
    func cancelCurrent() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        if activeLanguage != nil {
            _ = recorder.stop()
            SystemAudio.restoreOutput()
            activeLanguage = nil
            toggledOn = nil
            micLevel = 0
        }
        status = .idle
    }

    private func transcribeAndInsert(_ lang: Language, samples: [Float]) async {
        guard models.ready(for: lang) else {
            setError("\(models.name(for: lang)) isn't ready — open Settings.")
            return
        }
        do {
            let text = try await withTimeout(seconds: 45) {
                try await self.models.transcribe(samples, language: lang)
            }
            if Task.isCancelled { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                setError("No speech detected")
                return
            }
            let cleaned = await cleanup(trimmed, lang: lang)
            if Task.isCancelled { return }
            lastText = cleaned
            let keepOnClipboard = UserDefaults.standard.bool(forKey: "copyToClipboard")
            inserter.insert(cleaned, keepOnClipboard: keepOnClipboard)
            HistoryStore.shared.add(text: cleaned, original: trimmed, language: lang.label)
            HistoryStore.shared.recordAudio(modelID: models.assignedID(for: lang),
                                            seconds: Double(samples.count) / 16_000.0)
            flashSuccess(lang)
        } catch {
            if Task.isCancelled { return }          // user cancelled — already idle
            if error is TimeoutError {
                setError("Timed out — try again")
            } else {
                setError(error.localizedDescription)
            }
        }
    }

    /// Fix known terms: on-device AI for mishears + a deterministic casing fix.
    private func cleanup(_ text: String, lang: Language) async -> String {
        guard CleanupScope.current.applies(to: lang) else { return text }
        let terms = VocabularyStore.shared.activeTerms
        guard !terms.isEmpty else { return text }

        var out = text
        let aiEnabled = (UserDefaults.standard.object(forKey: "aiCleanup") as? Bool) ?? true
        if aiEnabled, CleanupManager.shared.selectedIsReady {
            status = .refining(lang)
            if let corrected = try? await CleanupManager.shared.correct(text, terms: terms),
               AICleanupPrompt.isPlausible(original: text, candidate: corrected) {
                out = corrected
            }
        }
        return TextProcessor.canonicalize(out, terms: terms)
    }

    // MARK: - Transient HUD states

    private func flashSuccess(_ lang: Language) {
        status = .success(lang)
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            if status == .success(lang) { status = .idle }
        }
    }

    private func setError(_ message: String) {
        status = .error(message)
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if status == .error(message) { status = .idle }
        }
    }
}

struct TimeoutError: Error {}

/// Runs `operation`, throwing `TimeoutError` if it doesn't finish within `seconds`.
func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
