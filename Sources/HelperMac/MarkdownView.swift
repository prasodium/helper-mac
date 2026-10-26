import AppKit
import SwiftUI

/// Renders assistant replies: headings, lists, paragraphs and fenced code
/// blocks, with inline Markdown (bold, italics, `code`, links) inside text.
struct MarkdownView: View {
    let text: String

    private enum Block: Identifiable {
        case heading(Int, String)
        case bullet(String)
        case numbered(String, String)
        case paragraph(String)
        case code(String, String)
        var id: UUID { UUID() }
    }

    private var blocks: [(Int, Block)] { Array(Self.parse(text).enumerated()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks, id: \.0) { _, block in
                switch block {
                case .heading(let level, let s):
                    inline(s).font(level <= 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold())
                case .bullet(let s):
                    HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•"); inline(s) }
                case .numbered(let n, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 6) { Text(n).monospacedDigit(); inline(s) }
                case .paragraph(let s):
                    inline(s)
                case .code(let lang, let code):
                    CodeBlock(language: lang, code: code)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ s: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: s, options: options) { return Text(attributed) }
        return Text(s)
    }

    private static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var codeLang = ""
        var inCode = false

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(codeLang, codeLines.joined(separator: "\n")))
                    codeLines = []; inCode = false
                } else {
                    flushParagraph()
                    codeLang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCode = true
                }
                continue
            }
            if inCode { codeLines.append(line); continue }

            if trimmed.isEmpty { flushParagraph(); continue }
            if let m = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                flushParagraph()
                let level = trimmed[m].filter { $0 == "#" }.count
                blocks.append(.heading(level, String(trimmed[m.upperBound...])))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                blocks.append(.bullet(String(trimmed.dropFirst(2))))
            } else if let m = trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                flushParagraph()
                let marker = trimmed[..<m.upperBound].trimmingCharacters(in: .whitespaces)
                blocks.append(.numbered(marker, String(trimmed[m.upperBound...])))
            } else {
                paragraph.append(line)
            }
        }
        // A reply still streaming may end inside an unclosed fence.
        if inCode { blocks.append(.code(codeLang, codeLines.joined(separator: "\n"))) }
        flushParagraph()
        return blocks
    }
}

struct CodeBlock: View {
    let language: String
    let code: String
    @Local private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.quaternary.opacity(0.6))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .padding(10)
                    .textSelection(.enabled)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator))
    }
}
