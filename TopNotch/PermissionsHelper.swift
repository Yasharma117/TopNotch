import AVFoundation

public enum MicrophonePermissionState {
    case notDetermined
    case denied
    case authorized
}

public struct PermissionsHelper {
    public static func microphonePermissionState() -> MicrophonePermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        case .authorized:
            return .authorized
        @unknown default:
            return .denied
        }
    }

    public static func requestMicrophonePermission() async -> MicrophonePermissionState {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            return granted ? .authorized : .denied
        }
        return microphonePermissionState()
    }
}
