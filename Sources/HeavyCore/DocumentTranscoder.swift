import Foundation

public enum ContentFormat: String, CaseIterable, Codable, Sendable {
    case markdown
    case txt
    case rtf
    case pdf
    case html
    case javascript

    public var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .txt: return "txt"
        case .rtf: return "rtf"
        case .pdf: return "pdf"
        case .html: return "html"
        case .javascript: return "js"
        }
    }
}

public enum TranscoderError: Error, LocalizedError, Sendable {
    case unsupportedImportFormat(ContentFormat)
    case unsupportedExportFormat(ContentFormat)
    case invalidJavaScriptPayload

    public var errorDescription: String? {
        switch self {
        case .unsupportedImportFormat(let format):
            return "Importing \(format.rawValue) is only available when the required macOS frameworks are present."
        case .unsupportedExportFormat(let format):
            return "Exporting \(format.rawValue) is only available when the required macOS frameworks are present."
        case .invalidJavaScriptPayload:
            return "The JavaScript file does not contain a valid Heavy document payload."
        }
    }
}

public struct DocumentTranscoder: Sendable {
    public init() {}

    public func `import`(_ data: Data, format: ContentFormat, fileName: String = "Imported Document") throws -> EditorDocument {
        switch format {
        case .markdown:
            return importPlainText(String(decoding: data, as: UTF8.self), fileName: fileName, isMarkdown: true)
        case .txt:
            return importPlainText(String(decoding: data, as: UTF8.self), fileName: fileName, isMarkdown: false)
        case .html:
            return importHTML(String(decoding: data, as: UTF8.self), fileName: fileName)
        case .javascript:
            return try importJavaScript(String(decoding: data, as: UTF8.self), fileName: fileName)
        case .rtf:
            return try importRTF(data, fileName: fileName)
        case .pdf:
            return try importPDF(data, fileName: fileName)
        }
    }

    public func export(_ document: EditorDocument, format: ContentFormat) throws -> Data {
        switch format {
        case .markdown:
            return Data(markdown(for: document).utf8)
        case .txt:
            return Data(document.plainText().utf8)
        case .html:
            return Data(html(for: document).utf8)
        case .javascript:
            return try exportJavaScript(document)
        case .rtf:
            return try exportRTF(document)
        case .pdf:
            return try exportPDF(document)
        }
    }

    public func markdown(for document: EditorDocument) -> String {
        document.sections.map { section in
            let sectionBody = section.blocks.map(markdownLine(for:)).joined(separator: "\n\n")
            return "## \(section.title)\n\n\(sectionBody)"
        }.joined(separator: "\n\n")
    }

    public func html(for document: EditorDocument) -> String {
        let body = document.sections.map { section in
            let blocks = section.blocks.map(htmlLine(for:)).joined(separator: "\n")
            return "<section><h2>\(escapeHTML(section.title))</h2>\n\(blocks)\n</section>"
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html lang=\"en\">
        <head>
          <meta charset=\"utf-8\">
          <title>\(escapeHTML(document.title))</title>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private func markdownLine(for block: ContentBlock) -> String {
        switch block.style {
        case .heading:
            return "### \(block.text)"
        case .quote:
            return "> \(block.text)"
        case .checklist:
            return "- [\(block.checked ? "x" : " ")] \(block.text)"
        case .code:
            return "```\n\(block.text)\n```"
        case .image:
            if let image = block.image {
                return "![\(image.filename)](\(image.filename))"
            }
            return "![image]()"
        case .paragraph:
            return block.text
        }
    }

    private func htmlLine(for block: ContentBlock) -> String {
        switch block.style {
        case .heading:
            return "<h3>\(escapeHTML(block.text))</h3>"
        case .quote:
            return "<blockquote>\(escapeHTML(block.text))</blockquote>"
        case .checklist:
            let checked = block.checked ? " checked" : ""
            return "<label><input type=\"checkbox\" disabled\(checked)> \(escapeHTML(block.text))</label>"
        case .code:
            return "<pre><code>\(escapeHTML(block.text))</code></pre>"
        case .image:
            guard let image = block.image else { return "<figure></figure>" }
            let mediaType = image.format == .png ? "image/png" : "image/jpeg"
            let base64 = image.data.base64EncodedString()
            return "<figure><img alt=\"\(escapeHTML(image.filename))\" src=\"data:\(mediaType);base64,\(base64)\"></figure>"
        case .paragraph:
            return "<p>\(escapeHTML(block.text))</p>"
        }
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func importPlainText(_ text: String, fileName: String, isMarkdown: Bool) -> EditorDocument {
        let sections = splitSections(in: text, isMarkdown: isMarkdown).map { title, lines in
            ContentSection(
                title: title,
                blocks: parseBlocks(from: lines, isMarkdown: isMarkdown)
            )
        }

        return EditorDocument(title: sanitizedTitle(fileName), sections: sections.isEmpty ? [ContentSection(title: "Imported", blocks: [ContentBlock(style: .paragraph, text: text)])] : sections)
    }

    private func splitSections(in text: String, isMarkdown: Bool) -> [(String, [String])] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard isMarkdown else {
            return [("Imported", lines)]
        }

        var sections: [(String, [String])] = []
        var currentTitle = "Imported"
        var buffer: [String] = []

        for line in lines {
            if line.hasPrefix("## ") {
                if !buffer.isEmpty || sections.isEmpty {
                    sections.append((currentTitle, buffer))
                }
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                buffer = []
            } else {
                buffer.append(line)
            }
        }

        if !buffer.isEmpty || sections.isEmpty {
            sections.append((currentTitle, buffer))
        }

        return sections.filter { !$0.0.isEmpty || !$0.1.isEmpty }
    }

    private func parseBlocks(from lines: [String], isMarkdown: Bool) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var codeBuffer: [String] = []
        var isInsideCodeFence = false

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if isMarkdown && line == "```" {
                if isInsideCodeFence {
                    blocks.append(ContentBlock(style: .code, text: codeBuffer.joined(separator: "\n")))
                    codeBuffer.removeAll()
                }
                isInsideCodeFence.toggle()
                continue
            }

            if isInsideCodeFence {
                codeBuffer.append(rawLine)
                continue
            }

            guard !line.isEmpty else { continue }

            if isMarkdown && line.hasPrefix("### ") {
                blocks.append(ContentBlock(style: .heading, text: String(line.dropFirst(4))))
            } else if isMarkdown && line.hasPrefix("> ") {
                blocks.append(ContentBlock(style: .quote, text: String(line.dropFirst(2))))
            } else if isMarkdown && (line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ")) {
                let isChecked = line.hasPrefix("- [x] ")
                blocks.append(ContentBlock(style: .checklist, text: String(line.dropFirst(6)), checked: isChecked))
            } else if isMarkdown && line.hasPrefix("![") {
                let name = line.split(separator: "]", maxSplits: 1).first?.dropFirst() ?? "image"
                blocks.append(ContentBlock(style: .image, text: "", image: EmbeddedImage(filename: String(name), format: .png, data: Data())))
            } else {
                blocks.append(ContentBlock(style: .paragraph, text: rawLine))
            }
        }

        if blocks.isEmpty {
            blocks = [ContentBlock(style: .paragraph)]
        }

        return blocks
    }

    private func importHTML(_ html: String, fileName: String) -> EditorDocument {
        let normalized = html.replacingOccurrences(of: "\r", with: "")
        let sectionPattern = #"<section>(.*?)</section>"#
        let sectionRegex = try? NSRegularExpression(pattern: sectionPattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        let sectionMatches = sectionRegex?.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) ?? []

        let sections: [ContentSection] = sectionMatches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: normalized) else { return nil }
            let content = String(normalized[range])
            let title = extractFirstMatch(in: content, pattern: #"<h2>(.*?)</h2>"#) ?? "Imported"
            let blocks = parseHTMLBlocks(from: content)
            return ContentSection(title: decodeHTML(title), blocks: blocks)
        }

        if sections.isEmpty {
            return EditorDocument(title: sanitizedTitle(fileName), sections: [ContentSection(title: "Imported", blocks: [ContentBlock(style: .paragraph, text: stripHTML(from: html))])])
        }

        return EditorDocument(title: sanitizedTitle(fileName), sections: sections)
    }

    private func parseHTMLBlocks(from html: String) -> [ContentBlock] {
        let patterns: [(String, (String) -> ContentBlock)] = [
            (#"<h3>(.*?)</h3>"#, { ContentBlock(style: .heading, text: decodeHTML($0)) }),
            (#"<blockquote>(.*?)</blockquote>"#, { ContentBlock(style: .quote, text: decodeHTML($0)) }),
            (#"<pre><code>(.*?)</code></pre>"#, { ContentBlock(style: .code, text: decodeHTML($0)) }),
            (#"<p>(.*?)</p>"#, { ContentBlock(style: .paragraph, text: decodeHTML($0)) }),
            (#"<label><input type=\"checkbox\" disabled( checked)?>\s*(.*?)</label>"#, {
                let cleaned = decodeHTML($0.replacingOccurrences(of: " checked", with: ""))
                return ContentBlock(style: .checklist, text: cleaned)
            }),
        ]

        var blocks: [ContentBlock] = []
        for (pattern, builder) in patterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
            let matches = regex?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? []
            for match in matches {
                guard let range = Range(match.range(at: match.numberOfRanges - 1), in: html) else { continue }
                blocks.append(builder(String(html[range])))
            }
        }

        return blocks.isEmpty ? [ContentBlock(style: .paragraph, text: stripHTML(from: html))] : blocks
    }

    private func stripHTML(from html: String) -> String {
        html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private func exportJavaScript(_ document: EditorDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = try encoder.encode(document)
        let script = "export const heavyDocument = \(String(decoding: payload, as: UTF8.self));\n"
        return Data(script.utf8)
    }

    private func importJavaScript(_ script: String, fileName: String) throws -> EditorDocument {
        let pattern = #"export const heavyDocument = (\{.*\});?"#
        guard let json = extractFirstMatch(in: script, pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            throw TranscoderError.invalidJavaScriptPayload
        }

        let decoder = JSONDecoder()
        return try decoder.decode(EditorDocument.self, from: Data(json.utf8))
    }

    private func extractFirstMatch(in input: String, pattern: String, options: NSRegularExpression.Options = []) -> String? {
        let regex = try? NSRegularExpression(pattern: pattern, options: options)
        guard let match = regex?.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: input) else {
            return nil
        }

        return String(input[range])
    }

    private func sanitizedTitle(_ fileName: String) -> String {
        URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    }
}
