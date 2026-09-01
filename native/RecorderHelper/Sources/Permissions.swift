import AVFoundation
import ScreenCaptureKit

struct Permissions {
    let screen: Bool
    let mic: Bool
}

enum PermissionCheck {
    static func micAuthorized() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestMic() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    // ScreenCaptureKit has no preflight call. Asking for shareable content is the
    // documented probe: it throws when the Screen Recording grant is missing.
    static func screenAuthorized() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return true
        } catch {
            Emit.log("screen probe failed: \(error)")
            return false
        }
    }

    static func current() async -> Permissions {
        Permissions(screen: await screenAuthorized(), mic: micAuthorized())
    }
}
