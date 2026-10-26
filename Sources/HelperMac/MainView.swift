import HelperCore
import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var state
    @AppStorage(Pref.alwaysOnTop) private var alwaysOnTop = true
    @AppStorage(Pref.windowOpacity) private var opacity = 1.0

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            ChatView()
            Divider().opacity(0.4)
            ComposerView()
        }
        .background(.regularMaterial)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $alwaysOnTop) { Image(systemName: alwaysOnTop ? "pin.fill" : "pin") }
                    .toggleStyle(.button).help("Keep Helper above other windows")
                Button { state.clearConversation() } label: { Image(systemName: "square.and.pencil") }
                    .help("New conversation").disabled(state.messages.isEmpty)
                SettingsLink { Image(systemName: "gearshape") }.help("Settings (⌘,)")
            }
        }
        .background(WindowAccessor(alwaysOnTop: alwaysOnTop, opacity: opacity))
        .frame(minWidth: 500, minHeight: 520)
    }
}

/// Reaches the hosting NSWindow for things SwiftUI can't express yet
/// (window level, translucency, being reachable from global shortcuts).
struct WindowAccessor: NSViewRepresentable {
    var alwaysOnTop: Bool
    var opacity: Double

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        MainWindow.shared.window = window
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = alwaysOnTop ? .floating : .normal
        window.alphaValue = CGFloat(max(0.35, min(1, opacity)))
        // Float above full-screen apps too while pinned.
        window.collectionBehavior = alwaysOnTop ? [.fullScreenAuxiliary, .moveToActiveSpace] : [.fullScreenPrimary]
    }
}

@MainActor
final class MainWindow {
    static let shared = MainWindow()
    weak var window: NSWindow?

    func toggle() {
        guard let window else { NSApp.activate(ignoringOtherApps: true); return }
        if window.isVisible && NSApp.isActive {
            window.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
