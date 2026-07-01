import Foundation
import Speech
import AVFoundation

/// On-device dictation via Apple's Speech framework. No download; built into macOS.
final class AppleSpeechEngine {
    static let shared = AppleSpeechEngine()

    private var recognizers: [String: SFSpeechRecognizer] = [:]
    private var task: SFSpeechRecognitionTask?

    private func locale(for language: Language) -> Locale {
        language == .bangla ? Locale(identifier: "bn-IN") : Locale(identifier: "en-US")
    }

    private func recognizer(for language: Language) -> SFSpeechRecognizer? {
        let id = locale(for: language).identifier
        if let r = recognizers[id] { return r }
        guard let r = SFSpeechRecognizer(locale: locale(for: language)) else { return nil }
        recognizers[id] = r
        return r
    }

    static var authorized: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }
    static var authDetermined: Bool { SFSpeechRecognizer.authorizationStatus() != .notDetermined }

    /// Ready = authorized AND an on-device recognizer exists for that language.
    func isReady(for language: Language) -> Bool {
        guard Self.authorized, let r = recognizer(for: language) else { return false }
        return r.isAvailable && r.supportsOnDeviceRecognition
    }

    static func requestAuth(_ completion: @escaping () -> Void = {}) {
        SFSpeechRecognizer.requestAuthorization { _ in
            DispatchQueue.main.async { completion() }
        }
    }

    func transcribe(_ samples: [Float], language: Language) async throws -> String {
        guard let recognizer = recognizer(for: language), recognizer.isAvailable else {
            throw NSError(domain: "Kotha", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "Apple dictation unavailable for \(language.label)."])
        }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count))) else {
            throw NSError(domain: "Kotha", code: 11)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            if let dst = buffer.floatChannelData?[0], let base = src.baseAddress {
                dst.update(from: base, count: samples.count)
            }
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.append(buffer)
        request.endAudio()

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            var resumed = false
            self.task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if !resumed { resumed = true; cont.resume(throwing: error) }
                    return
                }
                if let result, result.isFinal, !resumed {
                    resumed = true
                    cont.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}
