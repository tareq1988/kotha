import Foundation

/// Per-minute price (USD) for online transcription models. Published rates change,
/// so these are editable and persisted in UserDefaults; the values below are defaults.
enum CostRates {
    /// Default USD per minute of audio.
    static let defaults: [String: Double] = [
        "soniox": 0.0016667,  // async (file) transcription ≈ $0.10 / hour
        "openai": 0.0060,     // gpt-4o-transcribe, $0.006 / minute (≈ $0.36 / hour)
    ]

    private static func key(_ id: String) -> String { "rate.\(id)" }

    /// USD per minute for a model id.
    static func rate(for id: String) -> Double {
        if UserDefaults.standard.object(forKey: key(id)) != nil {
            return UserDefaults.standard.double(forKey: id.isEmpty ? "" : key(id))
        }
        return defaults[id] ?? 0
    }

    static func setRate(_ value: Double, for id: String) {
        UserDefaults.standard.set(max(0, value), forKey: key(id))
    }

    /// USD spent for the given audio seconds at the model's rate.
    static func cost(seconds: Double, modelID: String) -> Double {
        seconds / 60.0 * rate(for: modelID)
    }
}
