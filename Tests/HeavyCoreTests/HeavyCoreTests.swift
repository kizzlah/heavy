import Foundation
import Testing
@testable import HeavyCore

@Test func markdownExportIncludesSectionsAndChecklistState() throws {
    let document = EditorDocument(
        title: "Draft",
        sections: [
            ContentSection(
                title: "Intro",
                blocks: [
                    ContentBlock(style: .heading, text: "Welcome"),
                    ContentBlock(style: .checklist, text: "Ship build", checked: true),
                    ContentBlock(style: .checklist, text: "Review notes", checked: false),
                ]
            )
        ]
    )

    let markdown = DocumentTranscoder().markdown(for: document)

    #expect(markdown.contains("## Intro"))
    #expect(markdown.contains("### Welcome"))
    #expect(markdown.contains("- [x] Ship build"))
    #expect(markdown.contains("- [ ] Review notes"))
}

@Test func markdownImportPreservesFencedCodeBlocks() throws {
    let markdown = """
    ## Draft

    ```swift
    let message = "Heavy"
    print(message)
    ```
    """

    let document = try DocumentTranscoder().import(Data(markdown.utf8), format: .markdown, fileName: "draft.md")

    #expect(document.sections.count == 1)
    #expect(document.sections[0].blocks.count == 1)
    #expect(document.sections[0].blocks[0].style == .code)
    #expect(document.sections[0].blocks[0].text == "let message = \"Heavy\"\nprint(message)")
}

@Test func javascriptRoundTripPreservesDocument() throws {
    let transcoder = DocumentTranscoder()
    let image = EmbeddedImage(filename: "cover.png", format: .png, data: Data([0x89, 0x50]), source: "cover.png")
    let document = EditorDocument(
        title: "Draft",
        sections: [
            ContentSection(
                title: "Intro",
                blocks: [
                    ContentBlock(style: .paragraph, text: "Lead"),
                    ContentBlock(style: .checklist, text: "Done", checked: true),
                    ContentBlock(style: .image, image: image),
                ]
            )
        ],
        aiConfiguration: AIConfiguration(
            isEnabled: true,
            preferredModel: "gpt-5.6-luna",
            mcp: MCPServerConfiguration(isEnabled: true, endpoint: "http://localhost:3000", enabledSkills: ["Outline"])
        ),
        createdAt: Date(timeIntervalSince1970: 1_234),
        updatedAt: Date(timeIntervalSince1970: 5_678)
    )

    let exported = try transcoder.export(document, format: .javascript)
    let imported = try transcoder.import(exported, format: .javascript, fileName: "heavy.js")

    #expect(imported == document)
}

@Test func movingBlockAcrossSectionsReordersDocument() {
    var document = EditorDocument(
        title: "Draft",
        sections: [
            ContentSection(title: "One", blocks: [ContentBlock(style: .paragraph, text: "A")]),
            ContentSection(title: "Two", blocks: [ContentBlock(style: .paragraph, text: "B")]),
        ]
    )

    let sourceSectionID = document.sections[0].id
    let destinationSectionID = document.sections[1].id
    let blockID = document.sections[0].blocks[0].id

    document.moveBlock(blockID: blockID, from: sourceSectionID, to: destinationSectionID, before: nil)

    #expect(document.sections[0].blocks.isEmpty)
    #expect(document.sections[1].blocks.map(\.text) == ["B", "A"])
}

@Test func movingBlockWithinSectionPreservesRequestedOrder() {
    var document = EditorDocument(
        title: "Draft",
        sections: [
            ContentSection(
                title: "One",
                blocks: [
                    ContentBlock(style: .paragraph, text: "A"),
                    ContentBlock(style: .paragraph, text: "B"),
                    ContentBlock(style: .paragraph, text: "C"),
                ]
            )
        ]
    )

    let sectionID = document.sections[0].id
    let blockID = document.sections[0].blocks[0].id
    let targetID = document.sections[0].blocks[2].id

    document.moveBlock(blockID: blockID, from: sectionID, to: sectionID, before: targetID)

    #expect(document.sections[0].blocks.map(\.text) == ["B", "A", "C"])
}

@Test func builtInProcessorTrimsWhitespace() {
    var document = EditorDocument(
        title: "Draft",
        sections: [
            ContentSection(title: "  Intro  ", blocks: [ContentBlock(style: .paragraph, text: "  body  ")])
        ]
    )

    let processor = TrimWhitespaceProcessor()
    document = processor.process(document: document)

    #expect(document.sections[0].title == "Intro")
    #expect(document.sections[0].blocks[0].text == "body")
}
