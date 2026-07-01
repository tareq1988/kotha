import Foundation

/// Online transcription via OpenAI's audio transcription API (gpt-4o-transcribe).
final class OpenAITranscriber {
    enum E: LocalizedError {
        case noKey
        case server(String)
        var errorDescription: String? {
            switch self {
            case .noKey:         return "OpenAI API key not set — open Settings."
            case .server(let m): return "OpenAI: \(m)"
            }
        }
    }

    private let model = "gpt-4o-transcribe"
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    func transcribe(samples: [Float], sampleRate: Int, language: Language) async throws -> String {
        guard let key = SecretStore.shared.key(for: "openai"), !key.isEmpty else { throw E.noKey }
        let wav = WAV.encode(samples: samples, sampleRate: sampleRate)

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendString("\(value)\r\n")
        }
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        body.appendString("Content-Type: audio/wav\r\n\r\n")
        body.append(wav)
        body.appendString("\r\n")
        field("model", model)
        field("language", language == .bangla ? "bn" : "en")
        field("response_format", "json")
        body.appendString("--\(boundary)--\r\n")
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw E.server("no response") }
        guard (200..<300).contains(http.statusCode) else {
            throw E.server(String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return json?["text"] as? String ?? ""
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}
