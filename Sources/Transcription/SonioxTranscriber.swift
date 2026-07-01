import Foundation

/// Online Bangla transcription via the Soniox async (file) REST API.
/// Flow: upload file → create transcription → poll → fetch transcript → clean up.
final class SonioxTranscriber {
    enum SError: LocalizedError {
        case noKey
        case server(String)

        var errorDescription: String? {
            switch self {
            case .noKey:           return "Soniox API key not set — open Settings."
            case .server(let m):   return "Soniox: \(m)"
            }
        }
    }

    private let base = URL(string: "https://api.soniox.com")!
    private let model = "stt-async-v5"

    func transcribe(samples: [Float], sampleRate: Int, language: Language) async throws -> String {
        guard let key = SecretStore.shared.key(for: "soniox"), !key.isEmpty else { throw SError.noKey }

        let wav = WAV.encode(samples: samples, sampleRate: sampleRate)
        let fileID = try await uploadFile(wav, key: key)
        let transcriptionID: String
        do {
            transcriptionID = try await createTranscription(fileID: fileID, key: key, language: language)
        } catch {
            await delete("v1/files/\(fileID)", key: key)
            throw error
        }

        defer {
            Task { [base, key] in
                await Self.delete(base: base, "v1/transcriptions/\(transcriptionID)", key: key)
                await Self.delete(base: base, "v1/files/\(fileID)", key: key)
            }
        }

        try await waitUntilCompleted(transcriptionID, key: key)
        return try await fetchTranscript(transcriptionID, key: key)
    }

    // MARK: - Steps

    private func uploadFile(_ data: Data, key: String) async throws -> String {
        var req = request("v1/files", method: "POST", key: key)
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        body.appendString("Content-Type: audio/wav\r\n\r\n")
        body.append(data)
        body.appendString("\r\n--\(boundary)--\r\n")
        req.httpBody = body

        let json = try await send(req)
        guard let id = json["id"] as? String else { throw SError.server("upload returned no id") }
        return id
    }

    private func createTranscription(fileID: String, key: String, language: Language) async throws -> String {
        var req = request("v1/transcriptions", method: "POST", key: key)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let hints = language == .bangla ? ["bn", "en"] : ["en"]
        let payload: [String: Any] = [
            "file_id": fileID,
            "model": model,
            "language_hints": hints
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let json = try await send(req)
        guard let id = json["id"] as? String else { throw SError.server("create returned no id") }
        return id
    }

    private func waitUntilCompleted(_ id: String, key: String) async throws {
        for _ in 0..<240 {   // up to ~60s
            let json = try await send(request("v1/transcriptions/\(id)", method: "GET", key: key))
            switch json["status"] as? String {
            case "completed": return
            case "error":     throw SError.server(json["error_message"] as? String ?? "transcription failed")
            default:          try await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        throw SError.server("timed out waiting for transcription")
    }

    private func fetchTranscript(_ id: String, key: String) async throws -> String {
        let json = try await send(request("v1/transcriptions/\(id)/transcript", method: "GET", key: key))
        if let tokens = json["tokens"] as? [[String: Any]] {
            return tokens.compactMap { $0["text"] as? String }.joined()
        }
        return json["text"] as? String ?? ""
    }

    // MARK: - HTTP helpers

    private func request(_ path: String, method: String, key: String) -> URLRequest {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func send(_ req: URLRequest) async throws -> [String: Any] {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw SError.server("no HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw SError.server("HTTP \(http.statusCode): \(msg)")
        }
        guard !data.isEmpty else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private func delete(_ path: String, key: String) async {
        await Self.delete(base: base, path, key: key)
    }

    private static func delete(base: URL, _ path: String, key: String) async {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: req)
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}
