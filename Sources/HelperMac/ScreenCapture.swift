import AppKit
import CoreGraphics
import HelperCore
import ScreenCaptureKit

enum ScreenCaptureError: LocalizedError {
    case permissionDenied
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Helper needs Screen Recording permission to see your screen. Open System Settings > Privacy & Security > Screen & System Audio Recording, turn Helper on, then quit and reopen Helper."
        case .noDisplay: "No display found to capture."
        }
    }
}

/// Screen capture through ScreenCaptureKit. Helper's own windows are left
/// out of every capture so the assistant never ends up looking at itself.
enum ScreenCapture {
    static var hasAccess: Bool { CGPreflightScreenCaptureAccess() }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The display the mouse is on (falls back to the main display).
    static func display(in content: SCShareableContent) -> SCDisplay? {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
           let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
           let match = content.displays.first(where: { $0.displayID == id }) {
            return match
        }
        return content.displays.first
    }

    static func captureDisplay() async throws -> (image: CGImage, screen: NSScreen?) {
        guard CGPreflightScreenCaptureAccess() else {
            // Shows the system prompt the first time; afterwards points the user at Settings.
            _ = CGRequestScreenCaptureAccess()
            throw ScreenCaptureError.permissionDenied
        }
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        catch { throw ScreenCaptureError.permissionDenied }
        guard let display = display(in: content) else { throw ScreenCaptureError.noDisplay }

        let own = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let config = SCStreamConfiguration()
        let scale = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
        })?.backingScaleFactor ?? 2
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false
        config.capturesAudio = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
        }
        return (image, screen)
    }
}
