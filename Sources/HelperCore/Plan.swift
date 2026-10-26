import Foundation

/// Freemium plans. The same app is both Free and Pro: no activation key
/// means Free (limited features), a valid key unlocks everything.
public enum Plan: String, Codable, Sendable {
    case free
    case pro
}

public enum Feature: String, CaseIterable, Sendable {
    case ask, mcq, summarize, debug, explain, solve, brightness
    case documents, resume, githubProjects
    case screenshot, voice, translation

    public var label: String {
        switch self {
        case .ask: "Ask questions"
        case .mcq: "Solve MCQs"
        case .summarize: "Summarize"
        case .debug: "Debug"
        case .explain: "Explain code"
        case .solve: "Solve code"
        case .brightness: "Window transparency"
        case .documents: "Document library"
        case .resume: "Resume"
        case .githubProjects: "GitHub projects"
        case .screenshot: "Screen capture"
        case .voice: "Voice input"
        case .translation: "Live translation"
        }
    }
}

public enum PlanPolicy {
    /// Features available without an activation key: all of them. Helper for
    /// Mac has no paywall; `Plan` stays so licensing can be re-enabled by
    /// shrinking this set.
    public static let freeFeatures: Set<Feature> = Set(Feature.allCases)

    public static func isAllowed(_ plan: Plan, _ feature: Feature) -> Bool {
        plan == .pro || freeFeatures.contains(feature)
    }
}
