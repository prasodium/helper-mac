import HelperCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            APISettings().tabItem { Label("OpenAI", systemImage: "key") }
            LibrarySettings().tabItem { Label("Library", systemImage: "books.vertical") }
            TranslationSettings().tabItem { Label("Translation", systemImage: "captions.bubble") }
        }
        .frame(width: 520, height: 440)
    }
}

private struct GeneralSettings: View {
    @Environment(AppState.self) private var state
    @AppStorage(Pref.alwaysOnTop) private var alwaysOnTop = true
    @AppStorage(Pref.windowOpacity) private var opacity = 1.0
    @AppStorage(Pref.codingLanguage) private var codingLanguage = "auto"
    @AppStorage(Pref.model) private var model = "gpt-4o"
    @AppStorage(Pref.speakReplies) private var speakReplies = false
    @AppStorage(Pref.launchAtLogin) private var launchAtLogin = true

    var body: some View {
        Form {
            Section("Window") {
                Toggle("Keep Helper above other windows", isOn: $alwaysOnTop)
                LabeledContent("Transparency") {
                    HStack {
                        Slider(value: $opacity, in: 0.35...1)
                        Text("\(Int(opacity * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle("Open Helper at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in state.setLaunchAtLogin(on) }
            }
            Section("Answers") {
                Picker("Code language", selection: $codingLanguage) {
                    ForEach(CodingLanguages.all) { Text($0.name).tag($0.code) }
                }
                TextField("Model", text: $model)
                    .help("Any OpenAI chat model your key can use, for example gpt-4o or gpt-4o-mini.")
                Toggle("Read replies aloud", isOn: $speakReplies)
                    .disabled(!state.allowed(.voice))
            }
            Section("Keyboard shortcuts") {
                ForEach(Hotkeys.Action.allCases, id: \.self) { action in
                    LabeledContent(action.title) { Text(action.display).font(.system(.body, design: .monospaced)) }
                }
            }
            Section("Privacy") {
                Text("Helper is a normal, visible Mac app: it appears in screen shares and recordings like any other window. Your API key is stored in the Keychain and only ever sent to OpenAI.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct APISettings: View {
    @Environment(AppState.self) private var state
    @Local private var key = ""
    @Local private var token = ""

    var body: some View {
        Form {
            Section("OpenAI API key") {
                if state.hasAPIKey {
                    LabeledContent("Active key") {
                        HStack {
                            Text(state.apiKeyPreview).font(.system(.body, design: .monospaced))
                            Button("Remove", role: .destructive) { state.removeAPIKey() }
                        }
                    }
                }
                SecureField("sk-…", text: $key)
                HStack {
                    Button("Save key") { state.saveAPIKey(key); key = "" }.disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    Link("Get a key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                }
                Text("Stored in your Mac's Keychain. Helper talks to OpenAI directly; there is no Helper server in between.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("GitHub token (optional)") {
                SecureField("ghp-…", text: $token)
                HStack {
                    Button("Save token") { KeychainStore.set(token.trimmingCharacters(in: .whitespaces), for: "github-token"); token = "" }
                        .disabled(token.isEmpty)
                    Button("Remove", role: .destructive) { KeychainStore.remove("github-token") }
                }
                Text("Raises the GitHub rate limit from 60 to 5000 requests/hour when adding projects. No scopes needed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct LibrarySettings: View {
    @Environment(AppState.self) private var state
    @Local private var projectURL = ""

    var body: some View {
        @Bindable var state = state
        Form {
            Section("Resume") {
                let resume = state.library.first { $0.kind == .resume }
                if let resume {
                    LabeledContent(resume.fileName) {
                        Button("Remove", role: .destructive) { Task { await state.removeFromLibrary(resume.id) } }
                    }
                }
                Button(resume == nil ? "Choose resume…" : "Replace resume…") { pick(kind: .resume, multiple: false) }
            }
            Section("Documents") {
                ForEach(state.library.filter { $0.kind == .document }) { doc in
                    LabeledContent(doc.fileName) {
                        Button("Remove", role: .destructive) { Task { await state.removeFromLibrary(doc.id) } }
                    }
                }
                Button("Add documents…") { pick(kind: .document, multiple: true) }
                Text("PDF, DOCX, TXT or MD. Indexed once and searched on every question.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("GitHub projects") {
                ForEach(state.projects) { project in
                    LabeledContent("\(project.owner)/\(project.repo)") {
                        Button("Remove", role: .destructive) { state.removeProject(project.url) }
                    }
                }
                HStack {
                    TextField("https://github.com/you/project", text: $projectURL)
                    Button("Add") { let u = projectURL; projectURL = ""; Task { await state.addProject(url: u) } }
                        .disabled(projectURL.isEmpty)
                }
            }
            if !state.libraryStatus.isEmpty {
                Section { Text(state.libraryStatus).font(.callout).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .task { await state.refreshLibrary() }
    }

    private func pick(kind: KnowledgeDocument.Kind, multiple: Bool) {
        guard state.require(kind == .resume ? .resume : .documents) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = TextExtractor.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        panel.message = kind == .resume ? "Choose your resume" : "Choose documents to add"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { await state.addFiles(urls, kind: kind) }
    }
}

private struct TranslationSettings: View {
    @AppStorage(Pref.translationLanguage) private var language = "en"
    @AppStorage(Pref.translationSource) private var source = "system"

    var body: some View {
        Form {
            Section("Live translation") {
                Picker("Translate into", selection: $language) {
                    ForEach(TranslationLanguages.all) { Text($0.name).tag($0.code) }
                }
                Picker("Audio source", selection: $source) {
                    Text("Everything this Mac plays (meetings, videos)").tag("system")
                    Text("Microphone (people in the room)").tag("microphone")
                }
                .pickerStyle(.radioGroup)
            }
            Section {
                Text("Turn translation on with the captions button next to the message box. The spoken language is detected automatically, and subtitles appear while people are still talking. System audio needs Screen Recording permission; the microphone needs Microphone permission.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
