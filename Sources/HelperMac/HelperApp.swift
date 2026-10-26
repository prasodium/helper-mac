import AppKit
import HelperCore
import SwiftUI

@MainActor let appState = AppState()

@main
struct HelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Helper", id: "main") {
            MainView().environment(appState)
        }
        .defaultSize(width: 520, height: 720)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Conversation") { appState.clearConversation() }.keyboardShortcut("n")
            }
            CommandMenu("Capture") {
                Button("Capture Screen Region") { Task { await appState.captureRegion() } }
                Button("Analyze Screen") { Task { await appState.analyzeScreen() } }
                Button(appState.isRecording ? "Stop Voice Input" : "Start Voice Input") { Task { await appState.toggleRecording() } }
                Button(appState.isTranslating ? "Stop Live Translation" : "Start Live Translation") { Task { await appState.toggleTranslation() } }
            }
        }

        MenuBarExtra("Helper", systemImage: "sparkles") {
            MenuBarContent().environment(appState)
        }

        Settings {
            SettingsView().environment(appState)
        }
    }
}

struct MenuBarContent: View {
    var body: some View {
        Button("Show Helper") { MainWindow.shared.show() }
        Divider()
        Button("Capture Screen Region") { Task { await appState.captureRegion() } }
        Button("Analyze Screen") { Task { await appState.analyzeScreen() } }
        Button(appState.isRecording ? "Stop Voice Input" : "Voice Input") { Task { await appState.toggleRecording() } }
        Divider()
        SettingsLink { Text("Settings…") }
        Button("Quit Helper") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.registerDefaults()
        Task { @MainActor in
            appState.start()
            Hotkeys.shared.handler = { action in
                switch action {
                case .toggleWindow: MainWindow.shared.toggle()
                case .captureRegion: Task { await appState.captureRegion() }
                case .voice: Task { await appState.toggleRecording() }
                case .analyzeScreen: Task { await appState.analyzeScreen() }
                }
            }
            Hotkeys.shared.register()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in MainWindow.shared.show() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Hotkeys.shared.unregister()
    }
}
