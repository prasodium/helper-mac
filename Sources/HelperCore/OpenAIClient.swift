import Foundation

public enum OpenAIError: LocalizedError {
    case missingKey
    case http(status: Int, message: String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .missingKey: "No OpenAI API key set yet. Open Settings and paste your key first."
        case .http(let status, let message):
            status == 401 ? "Your OpenAI API key was rejected. Check it in Settings." : message
        case .badResponse: "OpenAI returned a response Helper couldn't read."
        }
    }
}

/// One piece of a chat message: text or an image.
public enum ContentPart: Sendable {
    case text(String)
    case imagePNG(Data)
    case imageJPEG(Data)

    var json: [String: Any] {
        switch self {
        case .text(let t): return ["type": "text", "text": t]
        case .imagePNG(let d): return ["type": "image_url", "image_url": ["url": "data:image/png;base64," + d.base64EncodedString()]]
        case .imageJPEG(let d): return ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + d.base64EncodedString()]]
        }
    }
}

public struct ChatMessage: Sendable {
    public enum Role: String, Sendable { case system, user, assistant }
    public var role: Role
    public var parts: [ContentPart]

    public init(role: Role, parts: [ContentPart]) { self.role = role; self.parts = parts }
    public init(role: Role, text: String) { self.init(role: role, parts: [.text(text)]) }

    var json: [String: Any] {
        // Plain string content when there is only text keeps requests small and
        // works with every chat model.
        if parts.count == 1, case .text(let t) = parts[0] { return ["role": role.rawValue, "content": t] }
        return ["role": role.rawValue, "content": parts.map(\.json)]
    }
}

/// Minimal OpenAI REST client (chat streaming, embeddings, speech in/out).
/// The API key is the user's own and is only ever sent to api.openai.com.
public final class OpenAIClient: @unchecked Sendable {
    public static let defaultModel = "gpt-4o"
    public let apiKey: String
    public var model: String
    private let session: URLSession
    private let baseURL: URL

    public init(apiKey: String, model: String = OpenAIClient.defaultModel,
                session: URLSession = .shared, baseURL: URL = URL(string: "https://api.openai.com/v1")!) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
        self.baseURL = baseURL
    }

    public var hasKey: Bool { !apiKey.isEmpty }

    private func request(_ path: String, json: [String: Any]) throws -> URLRequest {
        guard hasKey else { throw OpenAIError.missingKey }
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        req.timeoutInterval = 120
        return req
    }

    private func chatBody(_ messages: [ChatMessage], maxTokens: Int, stream: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "messages": messages.map(\.json),
            "max_completion_tokens": maxTokens,
        ]
        if stream { body["stream"] = true }
        // Reasoning-capable families accept (and benefit from) a low effort
        // setting for snappy replies; classic chat models reject the field.
        if Self.supportsReasoningEffort(model) { body["reasoning_effort"] = "low" }
        return body
    }

    public static func supportsReasoningEffort(_ model: String) -> Bool {
        let m = model.lowercased()
        return m.hasPrefix("o1") || m.hasPrefix("o3") || m.hasPrefix("o4") || m.hasPrefix("gpt-5")
    }

    private static func throwIfFailed(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            var message = "OpenAI request failed (HTTP \(http.statusCode))."
            if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let err = obj["error"] as? [String: Any], let m = err["message"] as? String { message = m }
            throw OpenAIError.http(status: http.statusCode, message: message)
        }
    }

    /// One non-streaming completion.
    public func complete(_ messages: [ChatMessage], maxTokens: Int = 3000) async throws -> String {
        let req = try request("chat/completions", json: chatBody(messages, maxTokens: maxTokens, stream: false))
        let (data, response) = try await session.data(for: req)
        try Self.throwIfFailed(response, body: data)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { throw OpenAIError.badResponse }
        return content
    }

    /// Streams the answer piece by piece (server-sent events).
    public func stream(_ messages: [ChatMessage], maxTokens: Int = 3000) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let req = try request("chat/completions", json: chatBody(messages, maxTokens: maxTokens, stream: true))
                    let (bytes, response) = try await session.bytes(for: req)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        try Self.throwIfFailed(response, body: body)
                    }
                    for try await line in bytes.lines {
                        guard let delta = Self.parseStreamLine(line) else { continue }
                        if delta == Self.doneMarker { break }
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public static let doneMarker = "\u{0}DONE"

    /// Parses one SSE line into a text delta (nil = nothing to emit).
    public static func parseStreamLine(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return doneMarker }
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let text = delta["content"] as? String, !text.isEmpty else { return nil }
        return text
    }

    // MARK: Embeddings

    public func embed(_ texts: [String], model: String = "text-embedding-3-small") async throws -> [[Float]] {
        var all: [[Float]] = []
        for start in stride(from: 0, to: texts.count, by: 96) {
            let batch = Array(texts[start..<min(start + 96, texts.count)])
            let req = try request("embeddings", json: ["model": model, "input": batch])
            let (data, response) = try await session.data(for: req)
            try Self.throwIfFailed(response, body: data)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = obj["data"] as? [[String: Any]] else { throw OpenAIError.badResponse }
            let sorted = items.sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
            for item in sorted {
                guard let values = item["embedding"] as? [Double] else { throw OpenAIError.badResponse }
                all.append(values.map(Float.init))
            }
        }
        return all
    }

    // MARK: Speech

    /// Speech to text. `fileName` decides the container the API expects (.m4a, .wav, ...).
    public func transcribe(audio: Data, fileName: String = "audio.m4a", mimeType: String = "audio/m4a") async throws -> String {
        guard hasKey else { throw OpenAIError.missingKey }
        let boundary = "helper-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model", "whisper-1")
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, response) = try await session.data(for: req)
        try Self.throwIfFailed(response, body: data)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["text"] as? String else { throw OpenAIError.badResponse }
        return text
    }

    /// Text to speech; returns MP3 data.
    public func speech(_ text: String, voice: String = "alloy") async throws -> Data {
        let req = try request("audio/speech", json: ["model": "tts-1", "voice": voice, "input": String(text.prefix(4000))])
        let (data, response) = try await session.data(for: req)
        try Self.throwIfFailed(response, body: data)
        return data
    }
}
