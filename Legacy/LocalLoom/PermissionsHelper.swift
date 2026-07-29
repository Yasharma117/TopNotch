import AVFoundation

public enum MicrophonePermissionState {
    case notDetermined
    case denied
    case authorized
}

public struct PermissionsHelper {
    public static func microphonePermissionState() -> MicrophonePermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .granted:
            return .authorized
        @unknown default:
            return .denied
        }
    }

    public static func requestMicrophonePermission() async -> MicrophonePermissionState {
        if AVAudioApplication.shared.recordPermission == .undetermined {
            return await withCheckedContinuation { continuation in
                AVAudioApplication.shared.requestRecordPermission { granted in
                    continuation.resume(returning: granted ? .authorized : .denied)
                }
            }
        }
        return microphonePermissionState()
    }
}
