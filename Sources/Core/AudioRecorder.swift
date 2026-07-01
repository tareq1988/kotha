import AVFoundation
import CoreAudio
import AudioToolbox

/// Captures microphone audio and resamples it to 16 kHz mono Float32,
/// accumulating the samples for the duration of a hold.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()

    var onLevel: ((Float) -> Void)?
    private(set) var isRecording = false

    func start() throws {
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()

        let input = engine.inputNode
        applySelectedDevice(to: input)
        let inFormat = input.inputFormat(forBus: 0)
        guard inFormat.sampleRate > 0 else {
            throw NSError(domain: "Kotha", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No microphone input available"])
        }

        converter = AVAudioConverter(from: inFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        lock.lock(); let result = samples; lock.unlock()
        return result
    }

    /// Route the engine's input to the user-selected device (default if none chosen).
    private func applySelectedDevice(to input: AVAudioInputNode) {
        guard let uid = AudioDevices.selectedUID,
              let deviceID = AudioDevices.coreAudioID(forUID: uid),
              let audioUnit = input.audioUnit else { return }
        var dev = deviceID
        AudioUnitSetProperty(audioUnit,
                             kAudioOutputUnitProperty_CurrentDevice,
                             kAudioUnitScope_Global,
                             0,
                             &dev,
                             UInt32(MemoryLayout<AudioDeviceID>.size))
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let channel = out.floatChannelData else { return }

        let count = Int(out.frameLength)
        guard count > 0 else { return }
        let ptr = channel[0]

        var peak: Float = 0
        for i in 0..<count {
            let v = abs(ptr[i])
            if v > peak { peak = v }
        }
        onLevel?(min(1, peak * 3))

        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: ptr, count: count))
        lock.unlock()
    }
}
