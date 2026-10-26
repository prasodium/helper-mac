import AppKit

/// Reads an app's focused window title using the Accessibility API.
/// Without the Accessibility permission this quietly falls back to just the app name.
enum ActiveWindowContext {
    /// Returns "AppName — Window Title" for the frontmost app if available, else just "AppName".
    static func current() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

        // Don't report Helper's own window as context.
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return nil }

        return describe(app)
    }

    /// Returns "AppName — Window Title" for a specific app (used for the last app the user was in,
    /// since Helper itself is frontmost by the time a question is sent).
    static func describe(_ app: NSRunningApplication) -> String? {
        guard !app.isTerminated, let name = app.localizedName else { return nil }

        guard let title = focusedWindowTitle(pid: app.processIdentifier),
              !title.isEmpty else {
            return name
        }
        return "\(name) — \(title)"
    }

    private static func focusedWindowTitle(pid: pid_t) -> String? {
        let axApp = AXUIElementCreateApplication(pid)
        // A hung app must not stall sending a question.
        AXUIElementSetMessagingTimeout(axApp, 0.25)

        var windowRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &windowRef
        )
        guard status == .success, let window = windowRef else { return nil }

        let axWindow = window as! AXUIElement
        var titleRef: CFTypeRef?
        let titleStatus = AXUIElementCopyAttributeValue(
            axWindow, kAXTitleAttribute as CFString, &titleRef
        )
        guard titleStatus == .success else { return nil }
        return titleRef as? String
    }
}
