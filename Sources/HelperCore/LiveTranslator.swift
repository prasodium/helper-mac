import Foundation

public struct TranslationLanguage: Identifiable, Hashable, Sendable {
    public let code: String
    public let name: String
    public var id: String { code }
}

public enum TranslationLanguages {
    public static let all: [TranslationLanguage] = [
        .init(code: "en", name: "English"), .init(code: "hi", name: "Hindi"),
        .init(code: "es", name: "Spanish"), .init(code: "fr", name: "French"),
        .init(code: "de", name: "German"), .init(code: "pt", name: "Portuguese"),
        .init(code: "it", name: "Italian"), .init(code: "ja", name: "Japanese"),
        .init(code: "ko", name: "Korean"), .init(code: "zh", name: "Chinese"),
        .init(code: "ru", name: "Russian"),
    ]
}

public enum TranslationEvent: Sendable {
    case translated(String)   // translated subtitle text
    case source(String)       // transcript of what was said
    case error(String)
    case closed
}

/// Live subtitles for meeting audio through OpenAI's realtime translation
/// endpoint. 24 kHz mono PCM16 goes in; translated text streams back while
/// people are still speaking.
public final class LiveTranslator: @unchecked Sendable {
    public static let endpoint = URL(string: "wss://api.openai.com/v1/realtime/translations?model=gpt-realtime-translate")!

    private var task: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private let onEvent: @Sendable (TranslationEvent) -> Void
    private let lock = NSLock()

    public init(onEvent: @escaping @Sendable (TranslationEvent) -> Void) { self.onEvent = onEvent }

    public var isActive: Bool { lock.withLock { task != nil } }

    public func start(apiKey: String, language: String) async throws {
        guard !apiKey.isEmpty else { throw OpenAIError.missingKey }
        stop()
        var req = URLRequest(url: Self.endpoint)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: req)
        lock.withLock { self.task = task }
        task.resume()
        let update: [String: Any] = ["type": "session.update", "session": ["audio": ["output": ["language": language]]]]
        try await task.send(.string(String(data: try JSONSerialization.data(withJSONObject: update), encoding: .utf8)!))
        receive(on: task)
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                let wasCurrent = self.lock.withLock { () -> Bool in
                    guard self.task === task else { return false }
                    self.task = nil
                    return true
                }
                if wasCurrent { self.onEvent(.error(error.localizedDescription)); self.onEvent(.closed) }
            case .success(let message):
                if case .string(let text) = message { self.handle(text) }
                self.receive(on: task)
            }
        }
    }

    public func handle(_ text: String) {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let type = obj["type"] as? String else { return }
        switch type {
        case "session.output_transcript.delta":
            if let d = obj["delta"] as? String, !d.isEmpty { onEvent(.translated(d)) }
        case "session.input_transcript.delta":
            if let d = obj["delta"] as? String, !d.isEmpty { onEvent(.source(d)) }
        case "error":
            let message = (obj["error"] as? [String: Any])?["message"] as? String ?? "Translation error"
            onEvent(.error(message))
        case "session.closed":
            stop()
        default: break // translated audio is ignored: Helper shows subtitles only
        }
    }

    public func append(pcm16 data: Data) {
        guard let task = lock.withLock({ self.task }) else { return }
        let payload: [String: Any] = ["type": "session.input_audio_buffer.append", "audio": data.base64EncodedString()]
        guard let json = try? JSONSerialization.data(withJSONObject: payload), let text = String(data: json, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
    }

    public func stop() {
        let current = lock.withLock { () -> URLSessionWebSocketTask? in
            defer { task = nil }
            return task
        }
        guard let current else { return }
        current.send(.string(#"{"type":"session.close"}"#)) { _ in }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { current.cancel(with: .normalClosure, reason: nil) }
        onEvent(.closed)
    }
}
