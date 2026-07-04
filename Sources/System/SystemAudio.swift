import CoreAudio

/// Mutes the system's default output device while dictating, then restores the
/// previous state. Uses the device's mute property when available, falling back
/// to zeroing the main volume for devices that don't expose a settable mute.
enum SystemAudio {
    /// State captured at mute time so it can be restored on unmute.
    private enum Saved {
        case mute(AudioDeviceID)               // device was unmuted; we muted it
        case volume(AudioDeviceID, Float)      // device had no mute; we saved & zeroed volume
    }

    private static var saved: Saved?

    /// Mute the current default output device. No-op if already muted by us.
    static func muteOutput() {
        guard saved == nil, let device = defaultOutputDevice else { return }

        var muteAddr = address(kAudioDevicePropertyMute)
        if isSettable(device, &muteAddr) {
            // Only mute if it isn't already muted, so we don't unmute on restore.
            if getUInt32(device, &muteAddr) == 0, setUInt32(device, &muteAddr, 1) {
                saved = .mute(device)
            }
            return
        }

        var volAddr = address(kAudioDevicePropertyVolumeScalar)
        if isSettable(device, &volAddr), let prior = getFloat(device, &volAddr) {
            if setFloat(device, &volAddr, 0) {
                saved = .volume(device, prior)
            }
        }
    }

    /// Restore whatever we changed in `muteOutput()`.
    static func restoreOutput() {
        guard let state = saved else { return }
        saved = nil
        switch state {
        case .mute(let device):
            var addr = address(kAudioDevicePropertyMute)
            _ = setUInt32(device, &addr, 0)
        case .volume(let device, let prior):
            var addr = address(kAudioDevicePropertyVolumeScalar)
            _ = setFloat(device, &addr, prior)
        }
    }

    // MARK: - CoreAudio helpers

    private static var defaultOutputDevice: AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        return (status == noErr && device != 0) ? device : nil
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static func isSettable(_ device: AudioDeviceID, _ addr: inout AudioObjectPropertyAddress) -> Bool {
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &addr) else { return false }
        return AudioObjectIsPropertySettable(device, &addr, &settable) == noErr && settable.boolValue
    }

    private static func getUInt32(_ device: AudioDeviceID, _ addr: inout AudioObjectPropertyAddress) -> UInt32 {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value)
        return value
    }

    private static func setUInt32(_ device: AudioDeviceID, _ addr: inout AudioObjectPropertyAddress, _ value: UInt32) -> Bool {
        var value = value
        return AudioObjectSetPropertyData(
            device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    private static func getFloat(_ device: AudioDeviceID, _ addr: inout AudioObjectPropertyAddress) -> Float? {
        var value = Float(0)
        var size = UInt32(MemoryLayout<Float>.size)
        return AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func setFloat(_ device: AudioDeviceID, _ addr: inout AudioObjectPropertyAddress, _ value: Float) -> Bool {
        var value = value
        return AudioObjectSetPropertyData(
            device, &addr, 0, nil, UInt32(MemoryLayout<Float>.size), &value) == noErr
    }
}
