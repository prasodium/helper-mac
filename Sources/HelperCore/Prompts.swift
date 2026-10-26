import Foundation

/// How the assistant behaves for the whole conversation.
public enum AssistantMode: String, Sendable, CaseIterable, Identifiable {
    /// Everyday assistant: answers questions, explains code, debugs.
    case chat
    /// Mock interview: the assistant plays the interviewer so the user can practise.
    case practice

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chat: "Chat"
        case .practice: "Practice"
        }
    }
}

/// Quick-action buttons under the composer.
public enum QuickAction: String, CaseIterable, Identifiable, Sendable {
    case solve, mcq, explain, debug, summarize
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .solve: "Solve code"
        case .mcq: "Solve MCQ"
        case .explain: "Explain code"
        case .debug: "Debug"
        case .summarize: "Summarize"
        }
    }

    public var symbol: String {
        switch self {
        case .solve: "chevron.left.forwardslash.chevron.right"
        case .mcq: "checklist"
        case .explain: "text.magnifyingglass"
        case .debug: "ladybug"
        case .summarize: "text.alignleft"
        }
    }

    public var feature: Feature {
        switch self {
        case .solve: .solve
        case .mcq: .mcq
        case .explain: .explain
        case .debug: .debug
        case .summarize: .summarize
        }
    }

    /// Instruction wrapped around the user's text (or the captured screen).
    public var instruction: String {
        switch self {
        case .solve:
            return "Solve this programming problem. Start with the approach in plain words, note the time and space complexity, then give complete, working code with short comments on the key lines explaining why they are there."
        case .mcq:
            return "This is a multiple-choice question. State the correct option first (for example \"Answer: B\"), then explain in a few sentences why it is right and why the others are not."
        case .explain:
            return "Explain what this code does, step by step, in plain language. Point out anything surprising, and mention complexity or edge cases where relevant."
        case .debug:
            return "Find what is wrong here. Explain the root cause, then show the corrected code or the exact change to make."
        case .summarize:
            return "Summarize this clearly and concisely. Lead with the main point, then list the key details."
        }
    }
}

public struct PromptContext: Sendable {
    public var appName: String?
    public var resumeContext: String?
    public var documentContext: String?
    public var projectsContext: String?
    public var mode: AssistantMode = .chat
    public var codingLanguage: String = "auto"
    public init() {}
}

public enum Prompts {
    public static func system(_ context: PromptContext) -> String {
        var prompt = """
        You are Helper, a friendly and efficient AI assistant living on the user's Mac. You help with coding, writing, research and everyday tasks. Be concise, accurate and direct.
        Write math and Big-O as plain text (O(m * n), n^2), never LaTeX.
        Use Markdown: short paragraphs, bullet lists, and fenced code blocks with a language tag.
        When you write code, add short comments on the key lines explaining why they are there (not what the syntax does).
        If you are unsure or the provided context does not cover something, say so instead of inventing details.
        """

        if let projects = context.projectsContext, !projects.isEmpty {
            prompt += "\n\nThe user's own GitHub projects, with README content. Use them when relevant, and describe them as the user's own work:\n\n\(projects)"
        }
        if let app = context.appName, !app.isEmpty {
            prompt += "\n\nThe user is currently working in: \(app)."
        }
        if let resume = context.resumeContext, !resume.isEmpty {
            prompt += "\n\nExcerpts from the user's resume (ground truth about their background):\n\n\(resume)"
        }
        if let docs = context.documentContext, !docs.isEmpty {
            prompt += "\n\nRelevant excerpts from documents the user added to their library:\n\n\(docs)\n\nIf these answer the question, use them and name the document (\"According to X...\"). If they do not cover it, say so briefly and answer from general knowledge."
        }

        // Electron parity, chat mode only: answers about the user's own
        // background or projects are spoken as the user, in the first
        // person, never as "your resume" / "your project". Practice mode
        // is the exception: there the assistant is the interviewer, not
        // the candidate, so this rule must not apply.
        if context.mode != .practice, !((context.resumeContext ?? "").isEmpty && (context.projectsContext ?? "").isEmpty) {
            prompt += "\n\nWhen the question is about the user's own background, experience, or own projects, answer in the first person, as if the user is speaking about their own work (\"I built…\", \"I used…\"). Never say \"your resume\", \"your project\", or \"the user's project\" for their own work."
        }

        // MARK: - Mode-specific instructions
        switch context.mode {
        case .practice:
            prompt += "\n\n" + practiceInstruction
        case .chat:
            break // The default system prompt is enough
        }

        let language = CodingLanguages.instruction(for: context.codingLanguage)
        if !language.isEmpty {
            prompt += "\n\n" + language
        }

        return prompt
    }

    /// Mock-interview coach: the assistant interviews the user and gives feedback.
    public static let practiceInstruction = """
    MOCK INTERVIEW MODE: you are a friendly but rigorous interviewer helping the user practise. Ask exactly ONE question at a time and wait for their answer. Tailor questions to their resume and projects when excerpts are provided, and mix behavioural, technical and (when appropriate) coding questions. After each answer, give brief, specific feedback in this shape: **What worked**, **What to improve**, and, if useful, **A stronger way to say it** (a short example). Then ask the next question. Do not write answers for the user before they have tried; if they ask for a model answer, give one after feedback.
    """

    /// First message of a practice session.
    public static let practiceKickoff = "Let's start a mock interview. Introduce yourself in one sentence and ask your first question."

    public static func projectSummary(owner: String, repo: String, description: String?, language: String?, topics: [String], readme: String) -> String {
        """
        Summarize this GitHub project in a concise overview (under 150 words) covering what it does, its tech stack, and notable features. Write plain description text.
        Repo: \(owner)/\(repo)
        Description: \(description?.isEmpty == false ? description! : "N/A")
        Primary language: \(language?.isEmpty == false ? language! : "N/A")
        Topics: \(topics.isEmpty ? "N/A" : topics.joined(separator: ", "))
        README (may be partial): \(String(readme.prefix(6000)))
        """
    }

    /// Spoken questions (microphone voice input, not system audio): the transcript may
    /// contain filler words or rambling, so find the real question first, then answer
    /// in the Electron app's two-part voice format.
    public static let voiceInstruction = """
    VOICE QUESTION: the text below is a spoken question and may contain filler words or rambling. Identify the actual question first, then answer in exactly two parts: **Quick Answer** (short, direct) followed by **Detailed Explanation** (fuller context).
    """

    public static let screenDefault = "Look at this screen and tell me what I'm working on and anything worth noticing. Be concise."

    public static func regionInstruction(userQuestion: String?) -> String {
        let q = userQuestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let prefix = "Look at the selected area of the screen."
        if q.isEmpty {
            return prefix + " Describe what you see and solve or explain it step by step."
        }
        return prefix + " " + q
    }
}