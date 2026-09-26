import Foundation

public enum ImageFormat: String, Codable, CaseIterable, Sendable {
    case jpg
    case png

    public var fileExtension: String { rawValue }
}

public struct EmbeddedImage: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var filename: String
    public var format: ImageFormat
    public var data: Data
    public var source: String?

    public init(id: UUID = UUID(), filename: String, format: ImageFormat, data: Data, source: String? = nil) {
        self.id = id
        self.filename = filename
        self.format = format
        self.data = data
        self.source = source
    }
}

public enum BlockStyle: String, Codable, CaseIterable, Sendable {
    case paragraph
    case heading
    case quote
    case checklist
    case code
    case image
}

public struct ContentBlock: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var style: BlockStyle
    public var text: String
    public var checked: Bool
    public var image: EmbeddedImage?

    public init(
        id: UUID = UUID(),
        style: BlockStyle,
        text: String = "",
        checked: Bool = false,
        image: EmbeddedImage? = nil
    ) {
        self.id = id
        self.style = style
        self.text = text
        self.checked = checked
        self.image = image
    }
}

public struct ContentSection: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var blocks: [ContentBlock]

    public init(id: UUID = UUID(), title: String, blocks: [ContentBlock] = []) {
        self.id = id
        self.title = title
        self.blocks = blocks
    }
}

public struct MCPServerConfiguration: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var endpoint: String
    public var enabledSkills: [String]

    public init(isEnabled: Bool = false, endpoint: String = "", enabledSkills: [String] = []) {
        self.isEnabled = isEnabled
        self.endpoint = endpoint
        self.enabledSkills = enabledSkills
    }
}

public struct AIConfiguration: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var preferredModel: String
    public var mcp: MCPServerConfiguration

    public init(isEnabled: Bool = false, preferredModel: String = "gpt-5-mini", mcp: MCPServerConfiguration = .init()) {
        self.isEnabled = isEnabled
        self.preferredModel = preferredModel
        self.mcp = mcp
    }
}

public struct EditorDocument: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var sections: [ContentSection]
    public var aiConfiguration: AIConfiguration
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        sections: [ContentSection] = [],
        aiConfiguration: AIConfiguration = .init(),
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.sections = sections
        self.aiConfiguration = aiConfiguration
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public mutating func touch() {
        updatedAt = .now
    }

    public mutating func addSection(title: String = "New Section") {
        sections.append(ContentSection(title: title, blocks: [ContentBlock(style: .paragraph)]))
        touch()
    }

    public mutating func addBlock(_ block: ContentBlock, to sectionID: UUID) {
        guard let index = sections.firstIndex(where: { $0.id == sectionID }) else { return }
        sections[index].blocks.append(block)
        touch()
    }

    public mutating func updateBlock(sectionID: UUID, blockID: UUID, transform: (inout ContentBlock) -> Void) {
        guard let sectionIndex = sections.firstIndex(where: { $0.id == sectionID }),
              let blockIndex = sections[sectionIndex].blocks.firstIndex(where: { $0.id == blockID }) else {
            return
        }

        transform(&sections[sectionIndex].blocks[blockIndex])
        touch()
    }

    public mutating func moveSection(sectionID: UUID, before targetID: UUID?) {
        guard let sourceIndex = sections.firstIndex(where: { $0.id == sectionID }) else { return }
        let section = sections.remove(at: sourceIndex)

        if let targetID,
           let targetIndex = sections.firstIndex(where: { $0.id == targetID }) {
            sections.insert(section, at: targetIndex)
        } else {
            sections.append(section)
        }

        touch()
    }

    public mutating func moveBlock(blockID: UUID, from sourceSectionID: UUID, to destinationSectionID: UUID, before targetBlockID: UUID?) {
        guard let sourceSectionIndex = sections.firstIndex(where: { $0.id == sourceSectionID }),
              let sourceBlockIndex = sections[sourceSectionIndex].blocks.firstIndex(where: { $0.id == blockID }),
              let destinationSectionIndex = sections.firstIndex(where: { $0.id == destinationSectionID }) else {
            return
        }

        let block = sections[sourceSectionIndex].blocks.remove(at: sourceBlockIndex)

        if let targetBlockID,
           let destinationIndex = sections[destinationSectionIndex].blocks.firstIndex(where: { $0.id == targetBlockID }) {
            sections[destinationSectionIndex].blocks.insert(block, at: destinationIndex)
        } else {
            sections[destinationSectionIndex].blocks.append(block)
        }

        touch()
    }

    public func allTextBlocks() -> [ContentBlock] {
        sections.flatMap(\.blocks).filter { $0.style != .image }
    }

    public func plainText() -> String {
        sections.map { section in
            let body = section.blocks.map { block in
                switch block.style {
                case .checklist:
                    return "- [\(block.checked ? "x" : " ")] \(block.text)"
                case .image:
                    return block.image.map { "[Image: \($0.filename)]" } ?? "[Image]"
                default:
                    return block.text
                }
            }.joined(separator: "\n")

            return ([section.title, body].filter { !$0.isEmpty }).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

public extension EditorDocument {
    static func sample() -> EditorDocument {
        EditorDocument(
            title: "Heavy Draft",
            sections: [
                ContentSection(
                    title: "Opening",
                    blocks: [
                        ContentBlock(style: .heading, text: "Write in blocks"),
                        ContentBlock(style: .paragraph, text: "Heavy organizes long-form writing into movable sections and blocks."),
                        ContentBlock(style: .checklist, text: "Refine the story structure", checked: true),
                    ]
                ),
                ContentSection(
                    title: "Research",
                    blocks: [
                        ContentBlock(style: .quote, text: "Great writing tools should disappear behind the work."),
                        ContentBlock(style: .code, text: "export const note = 'Portable content';"),
                    ]
                ),
            ]
        )
    }
}
