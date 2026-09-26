import Foundation
import HeavyCore

#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class EditorStore: ObservableObject {
    @Published var document: EditorDocument
    @Published var selectedSectionID: UUID?
    @Published var selectedFormat: ContentFormat
    @Published var selectedSkillName: String
    @Published var lastErrorMessage: String?
    @Published var lastExportURL: URL?

    let transcoder: DocumentTranscoder
    let availableSkills: [AdvancedSkill]

    init(
        document: EditorDocument = .sample(),
        transcoder: DocumentTranscoder = .init(),
        availableSkills: [AdvancedSkill] = BuiltInSkills.defaults
    ) {
        self.document = document
        self.transcoder = transcoder
        self.availableSkills = availableSkills
        self.selectedSectionID = document.sections.first?.id
        self.selectedFormat = .markdown
        self.selectedSkillName = availableSkills.first?.name ?? ""
    }

    var selectedSectionIndex: Int? {
        guard let selectedSectionID else { return nil }
        return document.sections.firstIndex(where: { $0.id == selectedSectionID })
    }

    func addSection() {
        document.addSection(title: "Section \(document.sections.count + 1)")
        selectedSectionID = document.sections.last?.id
    }

    func addBlock(style: BlockStyle, to sectionID: UUID) {
        let block: ContentBlock
        switch style {
        case .heading:
            block = ContentBlock(style: .heading, text: "Heading")
        case .quote:
            block = ContentBlock(style: .quote, text: "Quoted insight")
        case .checklist:
            block = ContentBlock(style: .checklist, text: "Checklist item")
        case .code:
            block = ContentBlock(style: .code, text: "console.log('Heavy');")
        case .image:
            block = ContentBlock(style: .image)
        case .paragraph:
            block = ContentBlock(style: .paragraph, text: "Start writing…")
        }
        document.addBlock(block, to: sectionID)
    }

    func updateSectionTitle(_ title: String, sectionID: UUID) {
        guard let sectionIndex = document.sections.firstIndex(where: { $0.id == sectionID }) else { return }
        document.sections[sectionIndex].title = title
        document.touch()
    }

    func updateBlockText(_ text: String, sectionID: UUID, blockID: UUID) {
        document.updateBlock(sectionID: sectionID, blockID: blockID) { block in
            block.text = text
        }
    }

    func toggleChecklist(_ checked: Bool, sectionID: UUID, blockID: UUID) {
        document.updateBlock(sectionID: sectionID, blockID: blockID) { block in
            block.checked = checked
        }
    }

    func moveSection(payload: String, before targetSectionID: UUID?) {
        guard case let .section(sectionID) = DragPayload(payload) else { return }
        document.moveSection(sectionID: sectionID, before: targetSectionID)
    }

    func moveBlock(payload: String, into destinationSectionID: UUID, before targetBlockID: UUID?) {
        guard case let .block(sectionID, blockID) = DragPayload(payload) else { return }
        document.moveBlock(blockID: blockID, from: sectionID, to: destinationSectionID, before: targetBlockID)
    }

    func moveBlockToEnd(sectionID: UUID, blockID: UUID) {
        document.moveBlock(blockID: blockID, from: sectionID, to: sectionID, before: nil)
    }

    func embedImage(into sectionID: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let format: ImageFormat = url.pathExtension.lowercased() == "png" ? .png : .jpg
            let block = ContentBlock(style: .image, image: EmbeddedImage(filename: url.lastPathComponent, format: format, data: data))
            document.addBlock(block, to: sectionID)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func importDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .plainText,
            .rtf,
            .pdf,
            .html,
            .png,
            .jpeg,
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "js"),
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            if let imageFormat = resolveImageFormat(for: url) {
                try importImage(at: url, format: imageFormat)
                return
            }
            let data = try Data(contentsOf: url)
            let format = try resolveFormat(for: url)
            document = try transcoder.import(data, format: format, fileName: url.lastPathComponent)
            selectedSectionID = document.sections.first?.id
            selectedFormat = format
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func exportDocument() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType(for: selectedFormat)]
        panel.nameFieldStringValue = "\(document.title).\(selectedFormat.fileExtension)"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try transcoder.export(document, format: selectedFormat)
            try data.write(to: url)
            lastExportURL = url
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func runSelectedSkill() {
        guard document.aiConfiguration.isEnabled else {
            lastErrorMessage = "Enable AI before running skills."
            return
        }

        switch selectedSkillName {
        case "Outline":
            var pipeline = ModularContentProcessor(processors: [TrimWhitespaceProcessor()])
            pipeline.register(PromoteFirstParagraphProcessor())
            document = pipeline.run(on: document)
        case "Polish":
            document = ModularContentProcessor(processors: [TrimWhitespaceProcessor()]).run(on: document)
        case "Summarize":
            lastErrorMessage = "Summarize requires an AI or MCP-backed implementation."
        default:
            lastErrorMessage = "The selected skill is not implemented."
        }
    }

    func resolveFormat(for url: URL) throws -> ContentFormat {
        switch url.pathExtension.lowercased() {
        case "md", "markdown": return .markdown
        case "txt": return .txt
        case "rtf": return .rtf
        case "pdf": return .pdf
        case "html", "htm": return .html
        case "js", "mjs", "cjs": return .javascript
        default: throw EditorStoreError.unsupportedImportFormat(url.pathExtension)
        }
    }

    func resolveImageFormat(for url: URL) -> ImageFormat? {
        switch url.pathExtension.lowercased() {
        case "png": return .png
        case "jpg", "jpeg": return .jpg
        default: return nil
        }
    }

    func importImage(at url: URL, format: ImageFormat) throws {
        let data = try Data(contentsOf: url)
        let block = ContentBlock(style: .image, image: EmbeddedImage(filename: url.lastPathComponent, format: format, data: data))
        let section = ContentSection(title: sanitizedSectionTitle(for: url), blocks: [block])
        document = EditorDocument(title: sanitizedSectionTitle(for: url), sections: [section], aiConfiguration: document.aiConfiguration)
        selectedSectionID = section.id
    }

    func sanitizedSectionTitle(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    func contentType(for format: ContentFormat) -> UTType {
        switch format {
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        case .txt: return .plainText
        case .rtf: return .rtf
        case .pdf: return .pdf
        case .html: return .html
        case .javascript: return .javascript
        }
    }
}

enum EditorStoreError: LocalizedError {
    case unsupportedImportFormat(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedImportFormat(let pathExtension):
            return "Unsupported import format: \(pathExtension.isEmpty ? "unknown file type" : pathExtension)"
        }
    }
}

enum DragPayload {
    case section(UUID)
    case block(UUID, UUID)
    case unknown

    init(_ rawValue: String) {
        let parts = rawValue.split(separator: ":").map(String.init)
        if parts.count == 2, parts[0] == "section", let sectionID = UUID(uuidString: parts[1]) {
            self = .section(sectionID)
        } else if parts.count == 3, parts[0] == "block", let sectionID = UUID(uuidString: parts[1]), let blockID = UUID(uuidString: parts[2]) {
            self = .block(sectionID, blockID)
        } else {
            self = .unknown
        }
    }

    var rawValue: String {
        switch self {
        case .section(let sectionID):
            return "section:\(sectionID.uuidString)"
        case .block(let sectionID, let blockID):
            return "block:\(sectionID.uuidString):\(blockID.uuidString)"
        case .unknown:
            return "unknown"
        }
    }
}
#endif
