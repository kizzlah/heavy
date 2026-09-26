import Foundation

public struct AdvancedSkill: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var prompt: String

    public init(name: String, prompt: String) {
        self.name = name
        self.prompt = prompt
    }
}

public protocol DocumentProcessor: Sendable {
    var name: String { get }
    func process(document: EditorDocument) -> EditorDocument
}

public struct ModularContentProcessor: Sendable {
    private var processors: [any DocumentProcessor]

    public init(processors: [any DocumentProcessor] = []) {
        self.processors = processors
    }

    public mutating func register(_ processor: any DocumentProcessor) {
        processors.append(processor)
    }

    public func run(on document: EditorDocument) -> EditorDocument {
        processors.reduce(document) { partial, processor in
            processor.process(document: partial)
        }
    }
}

public struct TrimWhitespaceProcessor: DocumentProcessor {
    public let name = "Trim Whitespace"

    public init() {}

    public func process(document: EditorDocument) -> EditorDocument {
        var copy = document
        copy.sections = copy.sections.map { section in
            var section = section
            section.title = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
            section.blocks = section.blocks.map { block in
                var block = block
                if block.style != .image {
                    block.text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return block
            }
            return section
        }
        copy.touch()
        return copy
    }
}

public struct PromoteFirstParagraphProcessor: DocumentProcessor {
    public let name = "Promote Lead"

    public init() {}

    public func process(document: EditorDocument) -> EditorDocument {
        var copy = document
        for sectionIndex in copy.sections.indices {
            guard let firstTextBlockIndex = copy.sections[sectionIndex].blocks.firstIndex(where: { $0.style == .paragraph && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                continue
            }

            copy.sections[sectionIndex].blocks[firstTextBlockIndex].style = .heading
        }
        copy.touch()
        return copy
    }
}

public enum BuiltInSkills {
    public static let defaults: [AdvancedSkill] = [
        AdvancedSkill(name: "Outline", prompt: "Turn the current selection into an outline."),
        AdvancedSkill(name: "Polish", prompt: "Improve clarity while keeping the author's voice."),
        AdvancedSkill(name: "Summarize", prompt: "Summarize the current section in three bullet points."),
    ]
}
