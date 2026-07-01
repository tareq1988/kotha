import AVFoundation
import AppKit
import ApplicationServices
import CoreAudio

// MARK: - Permissions

enum Permissions {
    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func promptAccessibility() {
        AccessibilityHelper.requestIfNeeded()
        openPrivacy("Privacy_Accessibility")
    }

    static var microphone: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func requestMicrophone(_ completion: @escaping () -> Void = {}) {
        switch microphone {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { completion() }
            }
        case .denied, .restricted:
            openPrivacy("Privacy_Microphone")
        default:
            break
        }
    }

    static func openPrivacy(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Audio input devices

struct AudioInputDevice: Identifiable, Hashable {
    let id: String       // AVCaptureDevice.uniqueID
    let name: String
}

enum AudioDevices {
    static let selectionKey = "inputDeviceUID"

    static var selectedUID: String? {
        let uid = UserDefaults.standard.string(forKey: selectionKey)
        return (uid?.isEmpty == false) ? uid : nil
    }

    static func inputs() -> [AudioInputDevice] {
        let types: [AVCaptureDevice.DeviceType] = [.microphone, .external]
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .audio, position: .unspecified)
        return session.devices.map { AudioInputDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// Translate an AVCaptureDevice uniqueID into a Core Audio device ID.
    static func coreAudioID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioDeviceID(0)
        var cfUID = uid as CFString
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { uidPtr -> OSStatus in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                uidPtr,
                &dataSize,
                &deviceID)
        }
        return (status == noErr && deviceID != 0) ? deviceID : nil
    }
}
