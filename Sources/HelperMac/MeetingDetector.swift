import AppKit

/// Watches for meeting apps and reports when a meeting app becomes (or stops being) the frontmost app.
@MainActor
final class MeetingDetector {
    /// Bundle identifiers of common meeting apps.
    private let meetingBundleIDs: Set<String> = [
        "us.zoom.xos",                     // Zoom
        "com.microsoft.teams2",            // Microsoft Teams
        "com.microsoft.teams",             // Microsoft Teams (classic)
        "com.tinyspeck.slackmacgap",       // Slack
        "com.cisco.webexmeetingsapp",      // Webex
        "com.skype.Skype",                 // Skype
        "com.hnc.Discord",                 // Discord
        "com.apple.FaceTime"               // FaceTime
        // Google Meet runs in the browser, so it can't be detected reliably.
    ]

    private var observer: NSObjectProtocol?

    /// Starts observing app activation events.
    /// - Parameter onChange: Called when the meeting state may have changed.
    func start(onChange: @escaping (Bool) -> Void) {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The observer runs on the main queue, so it is safe to assume main-actor isolation.
            MainActor.assumeIsolated {
                guard let self else { return }
                onChange(self.isMeetingAppActive())
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    private func isMeetingAppActive() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier else {
            return false
        }
        return meetingBundleIDs.contains(bundleID)
    }
}