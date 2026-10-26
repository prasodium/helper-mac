import Foundation

public struct GitHubProject: Codable, Identifiable, Sendable {
    public var url: String
    public var owner: String
    public var repo: String
    public var overview: String
    public var readme: String
    public var addedAt: Date
    public var id: String { url }

    public init(url: String, owner: String, repo: String, overview: String, readme: String, addedAt: Date) {
        self.url = url; self.owner = owner; self.repo = repo
        self.overview = overview; self.readme = readme; self.addedAt = addedAt
    }
}

public struct GitHubRepoInfo: Sendable {
    public var description: String
    public var language: String
    public var topics: [String]
}

public enum GitHubError: LocalizedError {
    case badURL
    case notFound(String)
    case rateLimited(minutes: Int?)
    case failed(Int)

    public var errorDescription: String? {
        switch self {
        case .badURL: "That doesn't look like a GitHub project URL."
        case .notFound(let name): "Repository \"\(name)\" not found. Check the URL and that it's public."
        case .rateLimited(let minutes):
            "GitHub API rate limit reached (60 requests/hour without a token)"
                + (minutes.map { ", resets in ~\($0) min" } ?? "") + ". Add a GitHub token in Settings to raise this to 5000/hour."
        case .failed(let status): "GitHub request failed (HTTP \(status))."
        }
    }
}

public enum GitHubClient {
    public static func parse(_ url: String) -> (owner: String, repo: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"github\.com[/:]([^/\s]+)/([^/#?\s]+)"#, options: .caseInsensitive),
              let m = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              let o = Range(m.range(at: 1), in: url), let r = Range(m.range(at: 2), in: url) else { return nil }
        var repo = String(url[r])
        if repo.lowercased().hasSuffix(".git") { repo = String(repo.dropLast(4)) }
        return (String(url[o]), repo)
    }

    private static func request(_ path: String, token: String, accept: String) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(path)")!)
        req.setValue("Helper-Mac", forHTTPHeaderField: "User-Agent")
        req.setValue(accept, forHTTPHeaderField: "Accept")
        if !token.isEmpty { req.setValue("token \(token)", forHTTPHeaderField: "Authorization") }
        return req
    }

    public static func fetchInfo(owner: String, repo: String, token: String, session: URLSession = .shared) async throws -> GitHubRepoInfo {
        let (data, response) = try await session.data(for: request("\(owner)/\(repo)", token: token, accept: "application/vnd.github+json"))
        let http = response as? HTTPURLResponse
        switch http?.statusCode ?? 0 {
        case 200..<300:
            let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            return .init(description: obj["description"] as? String ?? "",
                         language: obj["language"] as? String ?? "",
                         topics: obj["topics"] as? [String] ?? [])
        case 404: throw GitHubError.notFound("\(owner)/\(repo)")
        case 403 where http?.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0":
            let reset = http?.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(Double.init)
            let minutes = reset.map { max(1, Int(ceil(($0 - Date().timeIntervalSince1970) / 60))) }
            throw GitHubError.rateLimited(minutes: minutes)
        default: throw GitHubError.failed(http?.statusCode ?? 0)
        }
    }

    /// A missing README shouldn't block adding a project.
    public static func fetchReadme(owner: String, repo: String, token: String, session: URLSession = .shared) async -> String {
        guard let (data, response) = try? await session.data(for: request("\(owner)/\(repo)/readme", token: token, accept: "application/vnd.github.raw")),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Persisted list of the user's own GitHub projects.
public final class ProjectStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var projects: [GitHubProject]

    public init(fileURL: URL = AppPaths.supportDirectory.appendingPathComponent("projects.json")) {
        self.fileURL = fileURL
        let decoder = JSONDecoder()
        projects = (try? Data(contentsOf: fileURL)).flatMap { try? decoder.decode([GitHubProject].self, from: $0) } ?? []
    }

    public func all() -> [GitHubProject] { lock.withLock { projects } }

    public func add(_ project: GitHubProject) {
        lock.withLock {
            projects.removeAll { $0.url == project.url }
            projects.append(project)
        }
        save()
    }

    public func remove(url: String) {
        lock.withLock { projects.removeAll { $0.url == url } }
        save()
    }

    /// Full cached READMEs, ready to drop into the system prompt.
    public func promptContext() -> String {
        all().map { "Project: \($0.owner)/\($0.repo)\n" + String(($0.readme.isEmpty ? $0.overview : $0.readme).prefix(6000)) }
            .joined(separator: "\n\n---\n\n")
    }

    private func save() {
        let snapshot = all()
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: fileURL, options: .atomic) }
    }
}
