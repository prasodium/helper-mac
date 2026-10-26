import Foundation
import PDFKit

public enum TextExtractionError: LocalizedError {
    case unsupported(String)
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .unsupported(let ext): "Unsupported file type \"\(ext)\". Use PDF, DOCX, TXT or MD."
        case .unreadable: "No readable text found in that file."
        }
    }
}

/// Reads plain text out of PDF, DOCX, TXT and MD files.
public enum TextExtractor {
    public static let supportedExtensions = ["pdf", "docx", "txt", "md"]

    public static func extract(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        let raw: String
        switch ext {
        case "pdf":
            guard let doc = PDFDocument(url: url) else { throw TextExtractionError.unreadable }
            raw = doc.string ?? ""
        case "docx":
            raw = try docxText(url)
        case "txt", "md":
            raw = try String(contentsOf: url, encoding: .utf8)
        default:
            throw TextExtractionError.unsupported(ext)
        }
        let clean = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TextExtractionError.unreadable }
        return clean
    }

    /// A .docx is a zip; the body text lives in word/document.xml.
    static func docxText(_ url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, "word/document.xml"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let xml = String(data: data, encoding: .utf8) else {
            throw TextExtractionError.unreadable
        }
        return plainText(fromWordXML: xml)
    }

    public static func plainText(fromWordXML xml: String) -> String {
        var text = xml
            .replacingOccurrences(of: "</w:p>", with: "\n")
            .replacingOccurrences(of: "<w:tab/>", with: "\t")
            .replacingOccurrences(of: "<w:br/>", with: "\n")
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, char) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'")] {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        return text
    }
}
