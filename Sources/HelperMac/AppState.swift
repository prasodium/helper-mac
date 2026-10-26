import AppKit
import HelperCore
import Observation
import ServiceManagement

struct ChatEntry: Identifiable, Codable {
    enum Role: String, Codable { case user, assistant }
    var id = UUID()
    var role: Role
    var text: String
    var isError = false
    /// Thumbnail of an attached capture (not persisted).
    var thumbnail: Data?

    enum CodingKeys: String, CodingKey { case id, role, text, isError }
}

@MainActor
@Observable
final class AppState {
    // MARK: Conversation
    var messages: [ChatEntry] = []
    var input = ""
    var attachment: CGImage?
    var isBusy = false
    var status = "Ready"
    var mode: AssistantMode = .chat

    // MARK: Capture / audio
    var isRecording = false
    var isScrollCapturing = false
    var scrollFrameCount = 0
    var isTranslating = false
    var subtitles = ""
    var sourceTranscript = ""

    // MARK: Account
    var plan: Plan = .free
    var licenseBlock: AccessResult?
    var upsellFeature: Feature?
    var showLicenseEntry = false
    var licenseMessage = ""
    var licenseBusy = false
    var licenseKeyPreview = ""
    var licenseProduct = ""
    var hasAPIKey = false
    var apiKeyPreview = ""

    // MARK: Library
    var library: [KnowledgeSummary] = []
    var projects: [GitHubProject] = []
    var libraryStatus = ""

    // MARK: Services
    let license = LicenseManager()
    let knowledge = KnowledgeBase()
    let projectStore = ProjectStore()
    private let recorder = VoiceRecorder()
    private let speaker = SpeechPlayer()
    private let selector = RegionSelector()
    private var translator: LiveTranslator?
    private var audioSource: TranslationAudioSource?
    private var scrollSession: ScrollCaptureSession?
    private var scrollTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    private var lastExternalApp: String?
    private var heartbeat: Timer?

    static let storeURL = URL(string: "https://prasodium.github.io/helper-store")!

    // MARK: Lifecycle

    init() {
        loadHistory()
        refreshKeyStatus()
        plan = license.plan
        refreshLicenseDetails()
        observeFrontmostApp()
        Task { await refreshLibrary() }
        projects = projectStore.all()
    }

    func start() {
        Task { await verifyLicense() }
        heartbeat = Timer.scheduledTimer(withTimeInterval: LicenseManager.heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.verifyLicense() }
        }
    }

    private func observeFrontmostApp() {
        let own = Bundle.main.bundleIdentifier
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != own else { return }
            let name = app.localizedName
            Task { @MainActor in self?.lastExternalApp = name }
        }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != own { lastExternalApp = front?.localizedName }
    }

    // MARK: Plan gating

    func allowed(_ feature: Feature) -> Bool { PlanPolicy.isAllowed(plan, feature) }

    /// Returns true if the feature may be used; otherwise shows the upgrade sheet.
    @discardableResult
    func require(_ feature: Feature) -> Bool {
        if allowed(feature) { return true }
        upsellFeature = feature
        return false
    }

    // MARK: API client

    func client() -> OpenAIClient {
        OpenAIClient(apiKey: KeychainStore.get("openai-api-key"),
                     model: UserDefaults.standard.string(forKey: Pref.model) ?? OpenAIClient.defaultModel)
    }

    func refreshKeyStatus() {
        let key = KeychainStore.get("openai-api-key")
        hasAPIKey = !key.isEmpty
        apiKeyPreview = KeychainStore.mask(key)
    }

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.set(trimmed, for: "openai-api-key")
        refreshKeyStatus()
    }

    func removeAPIKey() {
        KeychainStore.remove("openai-api-key")
        refreshKeyStatus()
    }

    // MARK: Sending

    func send(_ action: QuickAction? = nil) {
        let typed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if let action, !require(action.feature) { return }
        guard !isBusy else { return }

        if let attachment {
            guard require(.screenshot) else { return }
            let question = typed
            let instruction = action.map { "\($0.instruction)\n\n\(Prompts.regionInstruction(userQuestion: question))" }
                ?? Prompts.regionInstruction(userQuestion: question)
            sendImage(attachment, instruction: instruction, shown: question.isEmpty ? "Selected area" : question)
            self.attachment = nil
            input = ""
            return
        }

        if typed.isEmpty {
            // A quick action with nothing typed works on whatever is on screen.
            if let action { Task { await analyzeScreen(instruction: action.instruction, label: action.title) } }
            return
        }
        if action == nil, !require(.ask) { return }

        let prompt = action.map { "\($0.instruction)\n\n\(typed)" } ?? typed
        input = ""
        ask(prompt, shown: action.map { "\($0.title): \(typed)" } ?? typed)
    }

    private func ask(_ prompt: String, shown: String, parts extra: [ContentPart] = [], thumbnail: Data? = nil) {
        guard client().hasKey else {
            messages.append(.init(role: .user, text: shown, thumbnail: thumbnail))
            messages.append(.init(role: .assistant, text: OpenAIError.missingKey.localizedDescription, isError: true))
            return
        }
        messages.append(.init(role: .user, text: shown, thumbnail: thumbnail))
        messages.append(.init(role: .assistant, text: ""))
        isBusy = true
        status = "Thinking…"
        let replyID = messages[messages.count - 1].id
        let history = Array(messages.dropLast(2).suffix(10))
        let openai = client()

        streamTask = Task {
            do {
                var context = PromptContext()
                context.appName = lastExternalApp
                context.mode = mode
                context.codingLanguage = UserDefaults.standard.string(forKey: Pref.codingLanguage) ?? "auto"
                if plan == .pro {
                    context.resumeContext = try? await knowledge.relevantContext(for: prompt, kind: .resume, topK: 4, client: openai)
                    context.documentContext = try? await knowledge.relevantContext(for: prompt, kind: .document, topK: 5, client: openai)
                    context.projectsContext = projectStore.promptContext()
                }

                var chat = [ChatMessage(role: .system, text: Prompts.system(context))]
                for entry in history where !entry.isError && !entry.text.isEmpty {
                    chat.append(.init(role: entry.role == .user ? .user : .assistant, text: entry.text))
                }
                chat.append(.init(role: .user, parts: [.text(prompt)] + extra))

                for try await delta in openai.stream(chat, maxTokens: 4000) {
                    append(delta, to: replyID)
                    status = "Writing…"
                }
                if let reply = messages.first(where: { $0.id == replyID }), reply.text.isEmpty {
                    update(replyID, text: "I didn't get a reply back. Try again.", isError: true)
                } else if UserDefaults.standard.bool(forKey: Pref.speakReplies), allowed(.voice),
                          let text = messages.first(where: { $0.id == replyID })?.text {
                    await speak(text)
                }
            } catch is CancellationError {
                // Stopped by the user; keep what was written.
            } catch {
                update(replyID, text: error.localizedDescription, isError: true)
            }
            isBusy = false
            status = "Ready"
            saveHistory()
        }
    }

    func stop() {
        streamTask?.cancel()
        isBusy = false
        status = "Ready"
    }

    private func append(_ delta: String, to id: UUID) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[i].text += delta
    }

    private func update(_ id: UUID, text: String, isError: Bool) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[i].text = text
        messages[i].isError = isError
    }

    private func sendImage(_ image: CGImage, instruction: String, shown: String) {
        guard let png = ImageTools.visionPNG(image) else { return }
        let thumb = ImageTools.jpegData(ImageTools.resized(image, maxWidth: 360), quality: 0.7)
        ask(instruction, shown: shown, parts: [.imagePNG(png)], thumbnail: thumb)
    }

    // MARK: Screen features

    func analyzeScreen(instruction: String? = nil, label: String = "Analyze my screen") async {
        guard require(.screenshot), !isBusy else { return }
        guard client().hasKey else { ask("", shown: label); return }
        do {
            status = "Capturing screen…"
            let (image, _) = try await ScreenCapture.captureDisplay()
            sendImage(image, instruction: instruction ?? Prompts.screenDefault, shown: label)
        } catch {
            report(error)
        }
    }

    func captureRegion() async {
        guard require(.screenshot) else { return }
        do {
            status = "Select an area…"
            let (image, screen) = try await ScreenCapture.captureDisplay()
            guard let screen = screen ?? NSScreen.main else { return }
            let cropped = await selector.select(from: image, on: screen)
            status = "Ready"
            if let cropped {
                attachment = cropped
                NSApp.activate(ignoringOtherApps: true)
            }
        } catch {
            report(error)
        }
    }

    /// First call starts collecting frames while the user scrolls; the second finishes and asks.
    func toggleScrollCapture() async {
        if isScrollCapturing {
            scrollTask?.cancel()
            isScrollCapturing = false
            let session = scrollSession
            scrollSession = nil
            guard let composite = session?.finish() else { status = "Ready"; return }
            let typed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            input = ""
            let instruction = typed.isEmpty
                ? "These are screenshots of one long page I scrolled through, already stitched top to bottom. Read all of it, then respond to it: if it contains a question or problem, solve it; otherwise summarize it."
                : typed
            sendImage(composite, instruction: instruction, shown: "Scrolled capture (\(session?.frameCount ?? 0) screens)" + (typed.isEmpty ? "" : ": \(typed)"))
            return
        }
        guard require(.screenshot) else { return }
        guard ScreenCapture.hasAccess else { report(ScreenCaptureError.permissionDenied); _ = CGRequestScreenCaptureAccess(); return }
        let session = ScrollCaptureSession()
        scrollSession = session
        isScrollCapturing = true
        scrollFrameCount = 0
        status = "Scroll through the page…"
        scrollTask = Task {
            while !Task.isCancelled, !session.isFull {
                if let (image, _) = try? await ScreenCapture.captureDisplay() {
                    session.consider(image)
                    scrollFrameCount = session.frameCount
                }
                try? await Task.sleep(for: .milliseconds(700))
            }
            if session.isFull, isScrollCapturing { await toggleScrollCapture() }
        }
    }

    // MARK: Voice

    func toggleRecording() async {
        if isRecording {
            isRecording = false
            status = "Transcribing…"
            do {
                let audio = try recorder.stop()
                let text = try await client().transcribe(audio: audio)
                status = "Ready"
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                input = trimmed
                send()
            } catch {
                report(error)
            }
            return
        }
        guard require(.voice) else { return }
        guard client().hasKey else { report(OpenAIError.missingKey); return }
        do {
            try await recorder.start()
            isRecording = true
            status = "Listening…"
        } catch {
            report(error)
        }
    }

    func speak(_ text: String) async {
        guard require(.voice) else { return }
        do { try speaker.play(try await client().speech(text)) } catch { report(error) }
    }

    func stopSpeaking() { speaker.stop() }

    // MARK: Live translation

    func toggleTranslation() async {
        if isTranslating { stopTranslation(); return }
        guard require(.translation) else { return }
        let openai = client()
        guard openai.hasKey else { report(OpenAIError.missingKey); return }

        subtitles = ""
        sourceTranscript = ""
        let translator = LiveTranslator { [weak self] event in
            Task { @MainActor in self?.handleTranslation(event) }
        }
        let source: TranslationAudioSource = UserDefaults.standard.string(forKey: Pref.translationSource) == "microphone"
            ? MicrophoneCapture() : SystemAudioCapture()
        source.onPCM = { [weak translator] data in translator?.append(pcm16: data) }
        do {
            try await translator.start(apiKey: openai.apiKey, language: UserDefaults.standard.string(forKey: Pref.translationLanguage) ?? "en")
            try await source.start()
            self.translator = translator
            audioSource = source
            isTranslating = true
            status = "Translating live…"
        } catch {
            translator.stop()
            report(error)
        }
    }

    func stopTranslation() {
        audioSource?.stop()
        translator?.stop()
        audioSource = nil
        translator = nil
        isTranslating = false
        status = "Ready"
    }

    private func handleTranslation(_ event: TranslationEvent) {
        switch event {
        case .translated(let t): subtitles = String((subtitles + t).suffix(700))
        case .source(let t): sourceTranscript = String((sourceTranscript + t).suffix(700))
        case .error(let m): report(NSError(domain: "Translation", code: 0, userInfo: [NSLocalizedDescriptionKey: m]))
        case .closed: if isTranslating { stopTranslation() }
        }
    }

    // MARK: Practice mode

    func setMode(_ new: AssistantMode) {
        guard new != mode else { return }
        if new == .practice, !require(.practice) { return }
        stop()
        mode = new
        messages.removeAll()
        saveHistory()
        if new == .practice { ask(Prompts.practiceKickoff, shown: "Start a mock interview") }
    }

    // MARK: Library (resume, documents, projects)

    func refreshLibrary() async { library = await knowledge.list() }

    func addFiles(_ urls: [URL], kind: KnowledgeDocument.Kind) async {
        guard require(kind == .resume ? .resume : .documents) else { return }
        let openai = client()
        for url in urls {
            libraryStatus = "Indexing \(url.lastPathComponent)…"
            do {
                let summary = try await knowledge.add(fileURL: url, kind: kind, client: openai)
                libraryStatus = "Added \(summary.fileName) (\(summary.chunkCount) sections)."
            } catch {
                libraryStatus = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        await refreshLibrary()
    }

    func removeFromLibrary(_ id: UUID) async {
        await knowledge.remove(id: id)
        await refreshLibrary()
    }

    func addProject(url: String) async {
        guard require(.githubProjects) else { return }
        guard let parsed = GitHubClient.parse(url) else { libraryStatus = GitHubError.badURL.localizedDescription; return }
        let token = KeychainStore.get("github-token")
        libraryStatus = "Fetching \(parsed.owner)/\(parsed.repo)…"
        do {
            async let info = GitHubClient.fetchInfo(owner: parsed.owner, repo: parsed.repo, token: token)
            async let readme = GitHubClient.fetchReadme(owner: parsed.owner, repo: parsed.repo, token: token)
            let (repoInfo, readmeText) = try await (info, readme)
            let summary = try await client().complete([.init(role: .user, text: Prompts.projectSummary(
                owner: parsed.owner, repo: parsed.repo, description: repoInfo.description,
                language: repoInfo.language, topics: repoInfo.topics, readme: readmeText))], maxTokens: 400)
            projectStore.add(.init(url: "https://github.com/\(parsed.owner)/\(parsed.repo)", owner: parsed.owner, repo: parsed.repo,
                                   overview: summary, readme: readmeText, addedAt: Date()))
            projects = projectStore.all()
            libraryStatus = "Added \(parsed.owner)/\(parsed.repo)."
        } catch {
            libraryStatus = error.localizedDescription
        }
    }

    func removeProject(_ url: String) {
        projectStore.remove(url: url)
        projects = projectStore.all()
    }

    // MARK: License

    func refreshLicenseDetails() {
        licenseKeyPreview = license.keyPreview
        licenseProduct = license.productName
        plan = license.plan
    }

    func verifyLicense() async {
        let result = await license.checkAccess()
        if result.allowed {
            licenseBlock = nil
            plan = result.plan
        } else {
            plan = .free
            licenseBlock = result
        }
        refreshLicenseDetails()
    }

    func activate(_ key: String) async {
        licenseBusy = true
        licenseMessage = ""
        let result = await license.activate(key)
        licenseBusy = false
        if result.ok {
            licenseBlock = nil
            showLicenseEntry = false
            upsellFeature = nil
            refreshLicenseDetails()
        } else {
            licenseMessage = result.message
        }
    }

    func deactivate() async {
        await license.deactivate()
        licenseBlock = nil
        refreshLicenseDetails()
    }

    func copyLicenseKey() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(license.storedKey, forType: .string)
    }

    func openStore(_ path: String = "#pricing") {
        NSWorkspace.shared.open(URL(string: Self.storeURL.absoluteString + "/" + path)!)
    }

    // MARK: Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            status = "Couldn't change the login item: \(error.localizedDescription)"
        }
    }

    // MARK: Errors & history

    func report(_ error: Error) {
        status = "Ready"
        isBusy = false
        messages.append(.init(role: .assistant, text: error.localizedDescription, isError: true))
    }

    private var historyURL: URL { AppPaths.supportDirectory.appendingPathComponent("history.json") }

    private func saveHistory() {
        let keep = Array(messages.filter { !$0.text.isEmpty }.suffix(200))
        if let data = try? JSONEncoder().encode(keep) { try? data.write(to: historyURL, options: .atomic) }
    }

    private func loadHistory() {
        if let data = try? Data(contentsOf: historyURL), let saved = try? JSONDecoder().decode([ChatEntry].self, from: data) {
            messages = saved
        }
    }

    func clearConversation() {
        stop()
        messages.removeAll()
        saveHistory()
    }
}
