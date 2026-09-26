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
                ]
            )
        ]
    )

    let markdown = DocumentTranscoder().markdown(for: document)

    #expect(markdown.contains("## Intro"))
    #expect(markdown.contains("### Welcome"))
    #expect(markdown.contains("- [x] Ship build"))
}

@Test func javascriptRoundTripPreservesDocument() throws {
    let transcoder = DocumentTranscoder()
    let document = EditorDocument.sample()

    let exported = try transcoder.export(document, format: .javascript)
    let imported = try transcoder.import(exported, format: .javascript, fileName: "heavy.js")

    #expect(imported.title == document.title)
    #expect(imported.sections.count == document.sections.count)
    #expect(imported.sections.first?.blocks.first?.text == document.sections.first?.blocks.first?.text)
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
