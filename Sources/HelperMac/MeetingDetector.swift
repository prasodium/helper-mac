import AppKit

/// Watches for meeting applications becoming frontmost and notifies on change.
@MainActor
final class MeetingDetector {
    /// Bundle identifiers of common meeting apps.
    private let meetingBundleIDs: Set<String> = [
        "us.zoom.xos",                  // Zoom
        "com.microsoft.teams2",         // Microsoft Teams (new)
        "com.microsoft.teams",          // Microsoft Teams (legacy)
        "com.tinyspeck.slackmacgap",    // Slack
        "com.cisco.webexmeetingsapp",   // Webex
        "com.skype.Skype",              // Skype
        "com.hnc.Discord",              // Discord
        "com.apple.FaceTime"            // FaceTime
        // Google Meet runs in the browser, so it can't be detected reliably.
    ]

    private var observer: NSObjectProtocol?
    private var lastState: Bool = false

    /// Start observing app activation. Calls `onChange` whenever the
    /// meeting state flips (including once up front if a meeting app is already frontmost).
    func start(onChange: @escaping @MainActor (Bool) -> Void) {
        stop()
        lastState = false

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The observer runs on the main queue, so it is safe to assume main-actor isolation.
            MainActor.assumeIsolated {
                guard let self else { return }
                // Switching to Helper itself (to ask something mid-meeting) doesn't end the meeting.
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier { return }
                let active = self.isMeetingAppActive()
                guard active != self.lastState else { return }
                self.lastState = active
                onChange(active)
            }
        }

        if isMeetingAppActive() {
            lastState = true
            onChange(true)
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
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
