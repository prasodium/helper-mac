import Foundation

/// Splits text into overlapping chunks on natural boundaries
/// (paragraphs, then lines, sentences, words) for embedding.
public enum TextChunker {
    public static func chunk(_ text: String, size: Int = 800, overlap: Int = 100) -> [String] {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }

        var pieces: [String] = []
        split(clean, size: size, separators: ["\n\n", "\n", ". ", " "], into: &pieces)

        var chunks: [String] = []
        var current = ""
        for piece in pieces {
            let candidate = current.isEmpty ? piece : current + " " + piece
            if candidate.count <= size {
                current = candidate
            } else {
                if !current.isEmpty { chunks.append(current) }
                // Carry the tail of the previous chunk so context isn't cut mid-thought.
                let tail = overlap > 0 ? String(current.suffix(overlap)) : ""
                current = tail.isEmpty ? piece : tail + " " + piece
                if current.count > size + overlap { current = piece }
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func split(_ text: String, size: Int, separators: [String], into out: inout [String]) {
        if text.count <= size { out.append(text); return }
        guard let sep = separators.first else {
            var start = text.startIndex
            while start < text.endIndex {
                let end = text.index(start, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
                out.append(String(text[start..<end]))
                start = end
            }
            return
        }
        for part in text.components(separatedBy: sep) {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            split(trimmed, size: size, separators: Array(separators.dropFirst()), into: &out)
        }
    }
}
