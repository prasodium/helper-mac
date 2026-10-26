import CoreGraphics
import Foundation
import HelperCore

// A tiny dependency-free check runner (XCTest isn't available with only the
// Command Line Tools). `swift run HelperChecks` exits non-zero on failure.

var failures = 0
var total = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool, file: String = #fileID, line: Int = #line) {
    total += 1
    if condition() { print("  ✓ \(name)") } else { failures += 1; print("  ✗ \(name)  (\(file):\(line))") }
}

func section(_ name: String) { print("\n\(name)") }

// MARK: Plans

section("Plans")
check("free can ask", PlanPolicy.isAllowed(.free, .ask))
check("free can debug", PlanPolicy.isAllowed(.free, .debug))
check("free cannot translate", !PlanPolicy.isAllowed(.free, .translation))
check("free cannot capture", !PlanPolicy.isAllowed(.free, .screenshot))
check("pro can do everything", Feature.allCases.allSatisfy { PlanPolicy.isAllowed(.pro, $0) })

// MARK: Coding language

section("Coding language")
check("auto adds no instruction", CodingLanguages.instruction(for: "auto").isEmpty)
check("python adds instruction", CodingLanguages.instruction(for: "python").contains("Python"))
check("validates codes", CodingLanguages.isValid("rust") && !CodingLanguages.isValid("cobol"))

// MARK: Prompts

section("Prompts")
var ctx = PromptContext()
ctx.resumeContext = "Built a compiler"
ctx.codingLanguage = "go"
let prompt = Prompts.system(ctx)
check("includes resume excerpts", prompt.contains("Built a compiler"))
check("includes coding language", prompt.contains("Go"))
check("chat mode has no interviewer instructions", !prompt.contains("MOCK INTERVIEW"))
check("background answers are first person", prompt.contains("first person") && prompt.contains("I built"))
check("voice answers split quick and detailed", Prompts.voiceInstruction.contains("Quick Answer") && Prompts.voiceInstruction.contains("Detailed Explanation"))
ctx.mode = .practice
check("practice mode asks one question at a time", Prompts.system(ctx).contains("ONE question at a time"))
check("practice mode does not use candidate first-person voice", !Prompts.system(ctx).contains("answer in the first person"))
check("region instruction without question", Prompts.regionInstruction(userQuestion: " ").contains("Identify"))
check("region instruction with question", Prompts.regionInstruction(userQuestion: "why?").contains("why?"))

// MARK: Chunking

section("Chunking")
let paragraph = String(repeating: "Swift is a modern language. ", count: 60)
let chunks = TextChunker.chunk(paragraph + "\n\n" + paragraph, size: 800, overlap: 100)
check("splits long text", chunks.count > 2)
check("chunks stay near the size limit", chunks.allSatisfy { $0.count <= 1000 })
check("empty text gives no chunks", TextChunker.chunk("  \n ").isEmpty)
check("short text stays whole", TextChunker.chunk("hello world") == ["hello world"])

// MARK: Vector math

section("Vector math")
check("identical vectors score 1", abs(VectorMath.cosine([1, 2, 3], [1, 2, 3]) - 1) < 1e-5)
check("orthogonal vectors score 0", abs(VectorMath.cosine([1, 0], [0, 1])) < 1e-6)
check("mismatched sizes score 0", VectorMath.cosine([1], [1, 2]) == 0)

// MARK: Text extraction

section("Text extraction")
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("helper-checks-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
let txt = tmp.appendingPathComponent("note.md")
try? "# Title\n\n\n\nBody text".write(to: txt, atomically: true, encoding: .utf8)
check("reads markdown", (try? TextExtractor.extract(from: txt)) == "# Title\n\nBody text")
check("rejects unsupported types", (try? TextExtractor.extract(from: tmp.appendingPathComponent("x.exe"))) == nil)
check("word xml to text", TextExtractor.plainText(fromWordXML: "<w:p><w:t>Hello &amp; welcome</w:t></w:p><w:p><w:t>Bye</w:t></w:p>") == "Hello & welcome\nBye\n")

// MARK: GitHub

section("GitHub URLs")
check("parses https url", GitHubClient.parse("https://github.com/prasodium/helper")?.repo == "helper")
check("strips .git", GitHubClient.parse("git@github.com:prasodium/helper.git")?.repo == "helper")
check("rejects other urls", GitHubClient.parse("https://example.com/a/b") == nil)

// MARK: Keychain

section("Keychain")
let account = "checks-\(UUID().uuidString)"
check("starts empty", KeychainStore.get(account).isEmpty)
KeychainStore.set("secret-1234", for: account)
check("round-trips", KeychainStore.get(account) == "secret-1234")
KeychainStore.set("secret-5678", for: account)
check("updates in place", KeychainStore.get(account) == "secret-5678")
KeychainStore.remove(account)
check("removes", KeychainStore.get(account).isEmpty)
check("masks all but the last four", KeychainStore.mask("sk-abcdef1234") == "••••1234")

// MARK: Streaming parser

section("OpenAI stream parsing")
check("parses a delta", OpenAIClient.parseStreamLine(#"data: {"choices":[{"delta":{"content":"Hi"}}]}"#) == "Hi")
check("ignores empty deltas", OpenAIClient.parseStreamLine(#"data: {"choices":[{"delta":{}}]}"#) == nil)
check("recognises the end marker", OpenAIClient.parseStreamLine("data: [DONE]") == OpenAIClient.doneMarker)
check("ignores non-data lines", OpenAIClient.parseStreamLine(": keep-alive") == nil)
check("reasoning effort only for reasoning models", OpenAIClient.supportsReasoningEffort("o3-mini") && !OpenAIClient.supportsReasoningEffort("gpt-4o"))

// MARK: PCM

section("PCM")
let floats: [Float] = [0, 1, -1, 2, 0.5]
let pcm = floats.withUnsafeBufferPointer { PCM.int16Data(fromFloat: $0) }
let ints = pcm.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
check("converts and clamps", ints == [0, 32767, -32767, 32767, 16384])

// MARK: Images & scroll stitching

section("Scroll stitching")

/// A tall synthetic "page" where every row has a distinct brightness.
func makePage(rows: Int, width: Int = 300) -> CGImage {
    var pixels = [UInt8](repeating: 0, count: width * rows * 4)
    for y in 0..<rows {
        let value = UInt8((y * 7 + (y / 13) * 29) % 251)
        for x in 0..<width {
            let i = (y * width + x) * 4
            pixels[i] = value; pixels[i + 1] = value; pixels[i + 2] = value; pixels[i + 3] = 255
        }
    }
    let ctx = CGContext(data: &pixels, width: width, height: rows, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}

let page = makePage(rows: 900)
func window(_ top: Int, _ height: Int) -> CGImage { page.cropping(to: CGRect(x: 0, y: top, width: page.width, height: height))! }

let session = ScrollCaptureSession()
check("first frame is captured", session.consider(window(0, 400)).captured)
check("identical frame adds nothing", !session.consider(window(0, 400)).captured)
check("scrolled frame is added", session.consider(window(250, 400)).captured)
check("further scroll is added", session.consider(window(500, 400)).captured)
check("three distinct frames recorded", session.frameCount == 3)
check("overlap removed: height is the page height (±3)", abs(session.height - 900) <= 3)
let composite = session.finish()
check("composite renders", composite != nil && abs((composite?.height ?? 0) - 900) <= 3)
check("no overlap found in unrelated content", ScrollCaptureSession.findOverlap(previous: Array(repeating: 10, count: 200), next: (0..<200).map { Float($0 % 200) }) == 0)
check("png encodes", ImageTools.pngData(page) != nil)
check("resize shrinks to width", ImageTools.resized(makePage(rows: 100, width: 2000), maxWidth: 1000).width == 1000)

// MARK: Licensing

section("Licensing")

final class MemoryStorage: LicenseStorage {
    var licenseKey = ""; var deviceID = ""; var lastCheckAt: Date?; var productName = ""
    func clear() { licenseKey = ""; deviceID = ""; lastCheckAt = nil; productName = "" }
}

final class FakeServer: LicenseTransport, @unchecked Sendable {
    var responses: [String: (Int, String)] = [:]
    var calls: [String] = []
    var offline = false
    func post(_ url: URL, json: [String: Any]) async throws -> (status: Int, body: Data) {
        calls.append(url.lastPathComponent)
        if offline { throw URLError(.notConnectedToInternet) }
        let r = responses[url.lastPathComponent] ?? (200, "{}")
        return (r.0, Data(r.1.utf8))
    }
}

func makeManager(_ server: FakeServer, _ storage: MemoryStorage, device: String = "dev-1", now: @escaping () -> Date = Date.init) -> LicenseManager {
    LicenseManager(serverURL: "https://example.test/license", storage: storage, transport: server, appVersion: "1.0.0",
                   deviceID: { device }, deviceName: { "Test Mac" }, now: now)
}

let goodKey = "HLP-AB12-CD34-EF56"
check("key format accepted", LicenseManager.isValidKeyFormat(goodKey))
check("bad key format rejected", !LicenseManager.isValidKeyFormat("HLP-123"))

func run(_ block: @escaping @Sendable () async -> Void) {
    let done = DispatchSemaphore(value: 0)
    Task { await block(); done.signal() }
    done.wait()
}

run {
    let server = FakeServer(), storage = MemoryStorage()
    let manager = makeManager(server, storage)
    check("no key means Free plan", manager.plan == .free)
    let free = await manager.checkAccess()
    check("free plan is allowed without contacting the server", free.allowed && free.plan == .free && server.calls.isEmpty)

    let bad = await manager.activate("nope")
    check("malformed key never reaches the server", !bad.ok && server.calls.isEmpty)

    server.responses["activate"] = (200, #"{"success":true,"data":{"license":{"product":{"name":"Helper v1"}}}}"#)
    let ok = await manager.activate(" " + goodKey.lowercased() + " ")
    check("activation succeeds (normalises the key)", ok.ok && storage.licenseKey == goodKey)
    check("product name is stored", manager.productName == "Helper v1")
    check("plan becomes Pro", manager.plan == .pro)
    check("key preview is masked", manager.keyPreview == "HLP-AB1…EF56")

    let beat = await manager.checkAccess()
    check("heartbeat allows Pro", beat.allowed && beat.plan == .pro)

    server.responses["heartbeat"] = (403, #"{"error":{"message":"License is suspended."}}"#)
    let suspended = await manager.heartbeat()
    check("403 suspension blocks", !suspended.allowed && suspended.reason == .suspended)

    server.responses["heartbeat"] = (403, #"{"error":{"message":"Please install a newer version of the app."}}"#)
    let outdated = await manager.heartbeat()
    check("403 outdated build asks for an update", outdated.reason == .updateRequired)

    server.responses["heartbeat"] = (404, "{}")
    let gone = await manager.heartbeat()
    check("404 clears the local key", !gone.allowed && storage.licenseKey.isEmpty)
}

run {
    let server = FakeServer(), storage = MemoryStorage()
    var clock = Date()
    let manager = makeManager(server, storage, now: { clock })
    server.responses["activate"] = (200, "{}")
    _ = await manager.activate(goodKey)
    server.offline = true
    let grace = await manager.heartbeat()
    check("offline within the grace period still works", grace.allowed)
    clock = clock.addingTimeInterval(8 * 86_400)
    let expired = await manager.heartbeat()
    check("offline past 7 days is blocked", !expired.allowed && expired.reason == .offlineExpired)
}

run {
    let server = FakeServer(), storage = MemoryStorage()
    server.responses["activate"] = (409, #"{"error":{"message":"Device limit reached."}}"#)
    let refused = await makeManager(server, storage).activate(goodKey)
    check("server refusal surfaces its message", !refused.ok && refused.message == "Device limit reached." && storage.licenseKey.isEmpty)

    server.responses["activate"] = (200, "{}")
    let a = makeManager(server, storage, device: "mac-A")
    _ = await a.activate(goodKey)
    let b = makeManager(server, storage, device: "mac-B")
    let moved = await b.heartbeat()
    check("a copied install on another Mac must re-activate", !moved.allowed && moved.reason == .notActivated && storage.licenseKey.isEmpty)

    _ = await a.activate(goodKey)
    server.calls.removeAll()
    await a.deactivate()
    check("deactivate clears local state and tells the server", storage.licenseKey.isEmpty && server.calls == ["deactivate"])
}

run {
    check("device id is stable and hashed", DeviceID.current() == DeviceID.current() && DeviceID.current().count == 64)
}

// MARK: Translation events

section("Live translation")
var events: [String] = []
let lock = NSLock()
let translator = LiveTranslator { event in
    lock.withLock {
        switch event {
        case .translated(let t): events.append("t:\(t)")
        case .source(let t): events.append("s:\(t)")
        case .error(let m): events.append("e:\(m)")
        case .closed: events.append("closed")
        }
    }
}
translator.handle(#"{"type":"session.output_transcript.delta","delta":"Hola"}"#)
translator.handle(#"{"type":"session.input_transcript.delta","delta":"Hello"}"#)
translator.handle(#"{"type":"error","error":{"message":"boom"}}"#)
translator.handle(#"{"type":"session.output_audio.delta","delta":"AAAA"}"#)
check("maps realtime events", events == ["t:Hola", "s:Hello", "e:boom"])

// MARK: Result

try? FileManager.default.removeItem(at: tmp)
print("\n\(total - failures)/\(total) checks passed")
exit(failures == 0 ? 0 : 1)
