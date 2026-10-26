import Foundation

public struct CodingLanguage: Identifiable, Hashable, Sendable {
    public let code: String
    public let name: String
    public var id: String { code }
}

public enum CodingLanguages {
    public static let all: [CodingLanguage] = [
        .init(code: "auto", name: "Auto (match the problem)"),
        .init(code: "python", name: "Python"),
        .init(code: "java", name: "Java"),
        .init(code: "cpp", name: "C++"),
        .init(code: "c", name: "C"),
        .init(code: "javascript", name: "JavaScript"),
        .init(code: "typescript", name: "TypeScript"),
        .init(code: "csharp", name: "C#"),
        .init(code: "go", name: "Go"),
        .init(code: "kotlin", name: "Kotlin"),
        .init(code: "swift", name: "Swift"),
        .init(code: "rust", name: "Rust"),
    ]

    public static func isValid(_ code: String) -> Bool { all.contains { $0.code == code } }

    /// Instruction appended to prompts; empty for "auto".
    public static func instruction(for code: String) -> String {
        guard let lang = all.first(where: { $0.code == code }), lang.code != "auto" else { return "" }
        return "CODING LANGUAGE: write every piece of code in \(lang.name), using idiomatic \(lang.name). "
            + "If the problem shows starter code or a function signature in another language, rewrite it in "
            + "\(lang.name). Only use another language if the user explicitly asks for it in this message."
    }
}
