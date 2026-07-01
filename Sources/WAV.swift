import Foundation

/// Minimal 16-bit PCM mono WAV encoder for uploading to Soniox.
enum WAV {
    static func encode(samples: [Float], sampleRate: Int) -> Data {
        var data = Data()

        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)
        let dataSize = UInt32(samples.count * 2)

        func put<T>(_ value: T) {
            var v = value
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        func putASCII(_ s: String) { data.append(s.data(using: .ascii)!) }

        putASCII("RIFF")
        put(UInt32(36 + dataSize))
        putASCII("WAVE")

        putASCII("fmt ")
        put(UInt32(16))            // subchunk size
        put(UInt16(1))             // PCM
        put(channels)
        put(UInt32(sampleRate))
        put(byteRate)
        put(blockAlign)
        put(bitsPerSample)

        putASCII("data")
        put(dataSize)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            put(Int16(clamped * 32_767))
        }
        return data
    }
}
