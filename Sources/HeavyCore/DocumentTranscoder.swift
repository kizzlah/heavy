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
                return "![\(image.filename)](\(image.source ?? image.filename))"
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
            if let source = image.source, image.data.isEmpty {
                return "<figure><img alt=\"\(escapeHTML(image.filename))\" src=\"\(escapeHTML(source))\"></figure>"
            }
            let mediaType: String
            switch image.format {
            case .png:
                mediaType = "image/png"
            case .jpg:
                mediaType = "image/jpeg"
            case .external:
                mediaType = "application/octet-stream"
            }
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

    func importPlainText(_ text: String, fileName: String, isMarkdown: Bool) -> EditorDocument {
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
                if !buffer.isEmpty || currentTitle != "Imported" {
                    sections.append((currentTitle, buffer))
                }
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                buffer = []
            } else {
                buffer.append(line)
            }
        }

        if !buffer.isEmpty || currentTitle != "Imported" || sections.isEmpty {
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

            if isMarkdown && isInsideCodeFence && line == "```" {
                blocks.append(ContentBlock(style: .code, text: codeBuffer.joined(separator: "\n")))
                codeBuffer.removeAll()
                isInsideCodeFence = false
                continue
            }

            if isMarkdown && !isInsideCodeFence && line.hasPrefix("```") {
                isInsideCodeFence = true
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
            } else if isMarkdown && (line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ")) {
                let isChecked = line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ")
                blocks.append(ContentBlock(style: .checklist, text: String(line.dropFirst(6)), checked: isChecked))
            } else if isMarkdown && line.hasPrefix("![") {
                let (filename, source) = parseMarkdownImageReference(in: line)
                let format = inferredImageFormat(from: source)
                blocks.append(ContentBlock(style: .image, text: "", image: EmbeddedImage(filename: filename, format: format, data: Data(), source: source)))
            } else {
                blocks.append(ContentBlock(style: .paragraph, text: rawLine))
            }
        }

        if isInsideCodeFence, !codeBuffer.isEmpty {
            blocks.append(ContentBlock(style: .code, text: codeBuffer.joined(separator: "\n")))
        }

        if blocks.isEmpty {
            blocks = [ContentBlock(style: .paragraph)]
        }

        return blocks
    }

    private func importHTML(_ html: String, fileName: String) -> EditorDocument {
        let normalized = html.replacingOccurrences(of: "\r", with: "")
        let sectionPattern = #"<section\b[^>]*>(.*?)</section>"#
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
            return EditorDocument(title: sanitizedTitle(fileName), sections: [ContentSection(title: "Imported", blocks: [ContentBlock(style: .paragraph, text: decodeHTML(stripHTML(from: html)))])])
        }

        return EditorDocument(title: sanitizedTitle(fileName), sections: sections)
    }

    private func parseHTMLBlocks(from html: String) -> [ContentBlock] {
        let pattern = #"<h3>.*?</h3>|<blockquote>.*?</blockquote>|<pre><code>.*?</code></pre>|<p>.*?</p>|<label><input type=\"checkbox\" disabled(?: checked)?>.*?</label>|<figure>.*?</figure>"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        let matches = regex?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? []
        var blocks: [ContentBlock] = []
        for match in matches {
            guard let range = Range(match.range, in: html) else { continue }
            let fragment = String(html[range])
            if fragment.lowercased().hasPrefix("<h3>") {
                blocks.append(ContentBlock(style: .heading, text: decodeHTML(stripWrappingTag(from: fragment, tag: "h3"))))
            } else if fragment.lowercased().hasPrefix("<blockquote>") {
                blocks.append(ContentBlock(style: .quote, text: decodeHTML(stripWrappingTag(from: fragment, tag: "blockquote"))))
            } else if fragment.lowercased().hasPrefix("<pre><code>") {
                blocks.append(ContentBlock(style: .code, text: decodeHTML(fragment.replacingOccurrences(of: "<pre><code>", with: "").replacingOccurrences(of: "</code></pre>", with: ""))))
            } else if fragment.lowercased().hasPrefix("<p>") {
                blocks.append(ContentBlock(style: .paragraph, text: decodeHTML(stripWrappingTag(from: fragment, tag: "p"))))
            } else if fragment.lowercased().hasPrefix("<label>") {
                let checked = fragment.contains(" checked")
                let text = fragment.replacingOccurrences(of: #"<label><input type=\"checkbox\" disabled(?: checked)?>\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: "</label>", with: "")
                blocks.append(ContentBlock(style: .checklist, text: decodeHTML(text), checked: checked))
            } else if fragment.lowercased().hasPrefix("<figure>"), let imageBlock = parseHTMLImageBlock(from: fragment) {
                blocks.append(imageBlock)
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

    private func stripWrappingTag(from fragment: String, tag: String) -> String {
        fragment
            .replacingOccurrences(of: "<\(tag)>", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "</\(tag)>", with: "", options: [.caseInsensitive])
    }

    private func parseMarkdownImageReference(in line: String) -> (filename: String, source: String) {
        let components = line.split(separator: "](", maxSplits: 1).map(String.init)
        let altText = components.first?.replacingOccurrences(of: "![", with: "") ?? "image"
        let source = components.count > 1 ? components[1].dropLast() : Substring(altText)
        let sourceString = String(source)
        let filename = URL(fileURLWithPath: sourceString).lastPathComponent
        return (filename.isEmpty ? altText : filename, sourceString)
    }

    private func inferredImageFormat(from source: String) -> ImageFormat {
        let lowercased = source.lowercased()
        if lowercased.hasSuffix(".jpg") || lowercased.hasSuffix(".jpeg") {
            return .jpg
        }
        if lowercased.hasSuffix(".png") {
            return .png
        }
        return .external
    }

    private func parseHTMLImageBlock(from fragment: String) -> ContentBlock? {
        guard let alt = extractFirstMatch(in: fragment, pattern: #"alt=\"(.*?)\""#),
              let source = extractFirstMatch(in: fragment, pattern: #"src=\"(.*?)\""#) else {
            return nil
        }

        if source.hasPrefix("data:"),
           let commaIndex = source.firstIndex(of: ",") {
            let metadata = String(source[..<commaIndex])
            let base64 = String(source[source.index(after: commaIndex)...])
            let format: ImageFormat = metadata.contains("image/jpeg") ? .jpg : .png
            let data = Data(base64Encoded: base64) ?? Data()
            return ContentBlock(style: .image, image: EmbeddedImage(filename: decodeHTML(alt), format: format, data: data))
        }

        return ContentBlock(style: .image, image: EmbeddedImage(filename: decodeHTML(alt), format: inferredImageFormat(from: source), data: Data(), source: source))
    }

    private func exportJavaScript(_ document: EditorDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = try encoder.encode(document)
        let script = "export const heavyDocument = \(String(decoding: payload, as: UTF8.self));\n"
        return Data(script.utf8)
    }

    private func importJavaScript(_ script: String, fileName: String) throws -> EditorDocument {
        guard let json = extractHeavyDocumentJSON(from: script) else {
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

    private func extractHeavyDocumentJSON(from script: String) -> String? {
        let declarationPattern = #"(?:export\s+)?(?:const|let|var)\s+heavyDocument\s*="#
        let regex = try? NSRegularExpression(pattern: declarationPattern)
        guard let match = regex?.firstMatch(in: script, range: NSRange(script.startIndex..., in: script)),
              let declarationRange = Range(match.range, in: script),
              let objectStart = script[declarationRange.upperBound...].firstIndex(of: "{") else {
            return nil
        }

        var depth = 0
        var currentIndex = objectStart
        var isEscaping = false
        var stringDelimiter: Character?

        while currentIndex < script.endIndex {
            let character = script[currentIndex]

            if isEscaping {
                isEscaping = false
            } else if let activeDelimiter = stringDelimiter {
                if character == "\\" {
                    isEscaping = true
                } else if character == activeDelimiter {
                    stringDelimiter = nil
                }
            } else {
                if character == "\"" || character == "'" {
                    stringDelimiter = character
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        let endIndex = script.index(after: currentIndex)
                        return String(script[objectStart..<endIndex])
                    }
                }
            }

            currentIndex = script.index(after: currentIndex)
        }

        return nil
    }

    private func sanitizedTitle(_ fileName: String) -> String {
        URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    }
}
