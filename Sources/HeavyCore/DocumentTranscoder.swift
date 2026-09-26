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
            let fence = "```\(block.codeLanguage?.isEmpty == false ? block.codeLanguage! : "")"
            return "\(fence)\n\(block.text)\n```"
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
            let attribute = block.codeLanguage.map { " data-language=\"\(escapeHTML($0))\"" } ?? ""
            return "<pre><code\(attribute)>\(escapeHTML(block.text))</code></pre>"
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
        var codeLanguage: String?

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if isMarkdown && isInsideCodeFence && line == "```" {
                blocks.append(ContentBlock(style: .code, text: codeBuffer.joined(separator: "\n"), codeLanguage: codeLanguage))
                codeBuffer.removeAll()
                isInsideCodeFence = false
                codeLanguage = nil
                continue
            }

            if isMarkdown && !isInsideCodeFence && line.hasPrefix("```") {
                isInsideCodeFence = true
                let infoString = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeLanguage = infoString.isEmpty ? nil : infoString
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
            blocks.append(ContentBlock(style: .code, text: codeBuffer.joined(separator: "\n"), codeLanguage: codeLanguage))
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
            return EditorDocument(title: sanitizedTitle(fileName), sections: [ContentSection(title: "Imported", blocks: [ContentBlock(style: .paragraph, text: decodeHTML(stripHTML(from: normalizedPlainTextHTML(from: html))))])])
        }

        return EditorDocument(title: sanitizedTitle(fileName), sections: sections)
    }

    private func parseHTMLBlocks(from html: String) -> [ContentBlock] {
        let pattern = #"<h3\b[^>]*>.*?</h3>|<blockquote\b[^>]*>.*?</blockquote>|<pre\b[^>]*>\s*<code\b[^>]*>.*?</code>\s*</pre>|<p\b[^>]*>.*?</p>|<label\b[^>]*>\s*<input\b[^>]*type=\"checkbox\"[^>]*>.*?</label>|<figure\b[^>]*>.*?</figure>"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        let matches = regex?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? []
        var blocks: [ContentBlock] = []
        for match in matches {
            guard let range = Range(match.range, in: html) else { continue }
            let fragment = String(html[range])
            if fragment.lowercased().hasPrefix("<h3") {
                blocks.append(ContentBlock(style: .heading, text: decodeHTML(stripWrappingTag(from: fragment, tag: "h3"))))
            } else if fragment.lowercased().hasPrefix("<blockquote") {
                blocks.append(ContentBlock(style: .quote, text: decodeHTML(stripWrappingTag(from: fragment, tag: "blockquote"))))
            } else if fragment.lowercased().hasPrefix("<pre") {
                let language = extractFirstMatch(in: fragment, pattern: #"data-language=\"(.*?)\""#)
                let code = fragment
                    .replacingOccurrences(of: #"<pre\b[^>]*>\s*<code\b[^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: #"</code>\s*</pre>"#, with: "", options: [.regularExpression, .caseInsensitive])
                blocks.append(ContentBlock(style: .code, text: decodeHTML(code), codeLanguage: language))
            } else if fragment.lowercased().hasPrefix("<p") {
                blocks.append(ContentBlock(style: .paragraph, text: decodeHTML(stripWrappingTag(from: fragment, tag: "p"))))
            } else if fragment.lowercased().hasPrefix("<label") {
                let checked = fragment.range(of: #"\bchecked\b"#, options: .regularExpression) != nil
                let text = fragment.replacingOccurrences(of: #"<label\b[^>]*>\s*<input\b[^>]*type=\"checkbox\"[^>]*>\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: "</label>", with: "")
                blocks.append(ContentBlock(style: .checklist, text: decodeHTML(text), checked: checked))
            } else if fragment.lowercased().hasPrefix("<figure"), let imageBlock = parseHTMLImageBlock(from: fragment) {
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

    private func normalizedPlainTextHTML(from html: String) -> String {
        html
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"</(p|div|li|section|article|h[1-6]|blockquote|pre)>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
    }

    private func decodeHTML(_ value: String) -> String {
        var decoded = value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&amp;", with: "&")

        let decimalRegex = try? NSRegularExpression(pattern: #"&#(\d+);"#)
        for match in (decimalRegex?.matches(in: decoded, range: NSRange(decoded.startIndex..., in: decoded)) ?? []).reversed() {
            guard let valueRange = Range(match.range(at: 1), in: decoded),
                  let scalar = UInt32(decoded[valueRange]),
                  let unicodeScalar = UnicodeScalar(scalar),
                  let fullRange = Range(match.range, in: decoded) else {
                continue
            }
            decoded.replaceSubrange(fullRange, with: String(Character(unicodeScalar)))
        }

        let hexRegex = try? NSRegularExpression(pattern: #"&#x([0-9A-Fa-f]+);"#)
        for match in (hexRegex?.matches(in: decoded, range: NSRange(decoded.startIndex..., in: decoded)) ?? []).reversed() {
            guard let valueRange = Range(match.range(at: 1), in: decoded),
                  let scalar = UInt32(decoded[valueRange], radix: 16),
                  let unicodeScalar = UnicodeScalar(scalar),
                  let fullRange = Range(match.range, in: decoded) else {
                continue
            }
            decoded.replaceSubrange(fullRange, with: String(Character(unicodeScalar)))
        }

        return decoded
    }

    private func stripWrappingTag(from fragment: String, tag: String) -> String {
        fragment
            .replacingOccurrences(of: #"^<\#(tag)\b[^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"</\#(tag)>$"#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    private func parseMarkdownImageReference(in line: String) -> (filename: String, source: String) {
        let components = line.split(separator: "](", maxSplits: 1).map(String.init)
        let altText = components.first?.replacingOccurrences(of: "![", with: "") ?? "image"
        let source = components.count > 1 ? components[1].dropLast() : Substring(altText)
        let sourceString = String(source)
        let filename = filenameFromImageSource(sourceString)
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
        guard let source = extractFirstMatch(in: fragment, pattern: #"src=\"(.*?)\""#) else {
            return nil
        }
        let alt = extractFirstMatch(in: fragment, pattern: #"alt=\"(.*?)\""#) ?? filenameFromImageSource(source)
        let filename = decodeHTML(alt.isEmpty ? "image" : alt)

        if source.hasPrefix("data:"),
           let commaIndex = source.firstIndex(of: ",") {
            let metadata = String(source[..<commaIndex])
            let base64 = String(source[source.index(after: commaIndex)...])
            let format: ImageFormat = metadata.contains("image/jpeg") ? .jpg : .png
            let data = Data(base64Encoded: base64) ?? Data()
            return ContentBlock(style: .image, image: EmbeddedImage(filename: filename, format: format, data: data))
        }

        return ContentBlock(style: .image, image: EmbeddedImage(filename: filename, format: inferredImageFormat(from: source), data: Data(), source: source))
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
        var document = try decoder.decode(EditorDocument.self, from: Data(json.utf8))
        if document.title.isEmpty {
            document.title = sanitizedTitle(fileName)
        }
        return document
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
        let scrubbedScript = maskJavaScriptCommentsAndStrings(in: script)
        let regex = try? NSRegularExpression(pattern: declarationPattern)
        guard let match = regex?.firstMatch(in: scrubbedScript, range: NSRange(scrubbedScript.startIndex..., in: scrubbedScript)),
              let declarationRange = Range(match.range, in: scrubbedScript) else {
            return nil
        }

        var cursor = skipJavaScriptTrivia(in: script, from: declarationRange.upperBound)
        let isWrappedInParentheses = cursor < script.endIndex && script[cursor] == "("
        if isWrappedInParentheses {
            cursor = skipJavaScriptTrivia(in: script, from: script.index(after: cursor))
        }

        guard cursor < script.endIndex, script[cursor] == "{",
              let json = extractBalancedJSONObject(in: script, from: cursor) else {
            return nil
        }

        if isWrappedInParentheses {
            let trailing = skipJavaScriptTrivia(in: script, from: json.endIndex)
            guard trailing < script.endIndex, script[trailing] == ")" else {
                return nil
            }
        }

        return json.payload
    }

    private func extractBalancedJSONObject(in script: String, from objectStart: String.Index) -> (payload: String, endIndex: String.Index)? {
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
                if character == "\"" {
                    stringDelimiter = character
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        let endIndex = script.index(after: currentIndex)
                        return (String(script[objectStart..<endIndex]), endIndex)
                    }
                }
            }

            currentIndex = script.index(after: currentIndex)
        }

        return nil
    }

    private func skipJavaScriptTrivia(in script: String, from start: String.Index) -> String.Index {
        var index = start

        while index < script.endIndex {
            if script[index].isWhitespace {
                index = script.index(after: index)
                continue
            }

            if script[index] == "/", script.index(after: index) < script.endIndex {
                let nextIndex = script.index(after: index)
                if script[nextIndex] == "/" {
                    index = script[index...].firstIndex(of: "\n") ?? script.endIndex
                    continue
                }

                if script[nextIndex] == "*" {
                    guard let range = script.range(of: "*/", range: nextIndex..<script.endIndex) else {
                        return script.endIndex
                    }
                    index = range.upperBound
                    continue
                }
            }

            break
        }

        return index
    }

    private func maskJavaScriptCommentsAndStrings(in script: String) -> String {
        var characters = Array(script)
        var index = 0
        var stringDelimiter: Character?
        var escaping = false

        while index < characters.count {
            let character = characters[index]

            if let delimiter = stringDelimiter {
                characters[index] = " "
                if escaping {
                    escaping = false
                } else if character == "\\" {
                    escaping = true
                } else if character == delimiter {
                    stringDelimiter = nil
                }
                index += 1
                continue
            }

            if character == "\"" || character == "'" {
                stringDelimiter = character
                characters[index] = " "
                index += 1
                continue
            }

            if character == "/", index + 1 < characters.count {
                if characters[index + 1] == "/" {
                    characters[index] = " "
                    characters[index + 1] = " "
                    index += 2
                    while index < characters.count, characters[index] != "\n" {
                        characters[index] = " "
                        index += 1
                    }
                    continue
                }

                if characters[index + 1] == "*" {
                    characters[index] = " "
                    characters[index + 1] = " "
                    index += 2
                    while index + 1 < characters.count {
                        if characters[index] == "*", characters[index + 1] == "/" {
                            characters[index] = " "
                            characters[index + 1] = " "
                            index += 2
                            break
                        }
                        characters[index] = " "
                        index += 1
                    }
                    continue
                }
            }

            index += 1
        }

        return String(characters)
    }

    private func filenameFromImageSource(_ source: String) -> String {
        if source.hasPrefix("data:") {
            return "embedded-image"
        }

        if let remoteURL = URL(string: source), let lastPathComponent = remoteURL.pathComponents.last, !lastPathComponent.isEmpty {
            return lastPathComponent
        }

        return source.split(separator: "/").last.map(String.init) ?? source
    }

    private func sanitizedTitle(_ fileName: String) -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawComponent = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        let withoutQuery = rawComponent.split(separator: "?").first.map(String.init) ?? rawComponent
        let title = (withoutQuery as NSString).deletingPathExtension
        return title.isEmpty ? trimmed : title
    }
}
