import Foundation

/// UserDefaults keys shared by Settings (via @AppStorage) and the app logic.
enum Pref {
    static let model = "model"
    static let codingLanguage = "codingLanguage"
    static let windowOpacity = "windowOpacity"
    static let alwaysOnTop = "alwaysOnTop"
    static let speakReplies = "speakReplies"
    static let translationLanguage = "translationLanguage"
    static let translationSource = "translationSource" // "system" | "microphone"
    static let launchAtLogin = "launchAtLogin"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            model: "gpt-4o",
            codingLanguage: "auto",
            windowOpacity: 1.0,
            alwaysOnTop: true,
            speakReplies: false,
            translationLanguage: "en",
            translationSource: "system",
            launchAtLogin: false,
        ])
    }
}
