import Foundation

public struct KnowledgeDocument: Codable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case resume, document }
    public var id: UUID
    public var fileName: String
    public var kind: Kind
    public var chunks: [String]
    public var vectors: [[Float]]
    public var addedAt: Date
}

public struct KnowledgeSummary: Identifiable, Sendable {
    public var id: UUID
    public var fileName: String
    public var kind: KnowledgeDocument.Kind
    public var chunkCount: Int
}

/// Local retrieval over the user's resume and documents: chunk, embed with
/// OpenAI, search by cosine similarity. Persisted on disk so documents
/// don't need re-embedding (and re-paying) after every launch.
public actor KnowledgeBase {
    private var documents: [KnowledgeDocument] = []
    private let fileURL: URL

    public init(fileURL: URL = AppPaths.supportDirectory.appendingPathComponent("knowledge.json")) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([KnowledgeDocument].self, from: data) {
            documents = saved
        }
    }

    public func list() -> [KnowledgeSummary] {
        documents.map { .init(id: $0.id, fileName: $0.fileName, kind: $0.kind, chunkCount: $0.chunks.count) }
    }

    public func hasResume() -> Bool { documents.contains { $0.kind == .resume } }
    public func hasDocuments() -> Bool { documents.contains { $0.kind == .document } }

    /// Reads, chunks and embeds a file. A new resume replaces the old one;
    /// re-adding a document with the same name replaces that document.
    @discardableResult
    public func add(fileURL url: URL, kind: KnowledgeDocument.Kind, client: OpenAIClient) async throws -> KnowledgeSummary {
        guard client.hasKey else { throw OpenAIError.missingKey }
        let text = try TextExtractor.extract(from: url)
        let chunks = TextChunker.chunk(text)
        let vectors = try await client.embed(chunks)
        let doc = KnowledgeDocument(id: UUID(), fileName: url.lastPathComponent, kind: kind,
                                    chunks: chunks, vectors: vectors, addedAt: Date())
        documents.removeAll { kind == .resume ? $0.kind == .resume : ($0.kind == .document && $0.fileName == doc.fileName) }
        documents.append(doc)
        save()
        return .init(id: doc.id, fileName: doc.fileName, kind: kind, chunkCount: chunks.count)
    }

    public func remove(id: UUID) {
        documents.removeAll { $0.id == id }
        save()
    }

    /// Top matching chunks of the given kind, tagged with their source file.
    public func relevantContext(for query: String, kind: KnowledgeDocument.Kind, topK: Int, client: OpenAIClient) async throws -> String {
        let pool = documents.filter { $0.kind == kind }
        guard !pool.isEmpty, client.hasKey else { return "" }
        guard let queryVector = try await client.embed([query]).first else { return "" }

        var scored: [(file: String, text: String, score: Float)] = []
        for doc in pool {
            for (i, vector) in doc.vectors.enumerated() where i < doc.chunks.count {
                scored.append((doc.fileName, doc.chunks[i], VectorMath.cosine(queryVector, vector)))
            }
        }
        scored.sort { $0.score > $1.score }
        return scored.prefix(topK)
            .map { kind == .document ? "[From \"\($0.file)\"]\n\($0.text)" : $0.text }
            .joined(separator: "\n\n---\n\n")
    }

    private func save() {
        if let data = try? JSONEncoder().encode(documents) { try? data.write(to: fileURL, options: .atomic) }
    }
}
