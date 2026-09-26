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
                    ContentBlock(style: .code, text: "print(\"Heavy\")", codeLanguage: "swift"),
                    ContentBlock(style: .quote, text: "Quoted"),
                    ContentBlock(style: .checklist, text: "Ship build", checked: true),
                    ContentBlock(style: .checklist, text: "Review notes", checked: false),
                    ContentBlock(style: .image, image: EmbeddedImage(filename: "cover.png", format: .png, data: Data(), source: "https://example.com/cover.png")),
                ]
            )
        ]
    )

    let markdown = DocumentTranscoder().markdown(for: document)

    #expect(markdown.contains("## Intro"))
    #expect(markdown.contains("### Welcome"))
    #expect(markdown.contains("```swift"))
    #expect(markdown.contains("> Quoted"))
    #expect(markdown.contains("- [x] Ship build"))
    #expect(markdown.contains("- [ ] Review notes"))
    #expect(markdown.contains("![cover.png](https://example.com/cover.png)"))
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
    #expect(document.sections[0].blocks[0].codeLanguage == "swift")
    #expect(document.sections[0].blocks[0].text == "let message = \"Heavy\"\nprint(message)")
}

@Test func markdownImportPreservesUnterminatedFencedCodeBlocks() throws {
    let markdown = """
    ## Draft

    ```
    print("Heavy")
    """

    let document = try DocumentTranscoder().import(Data(markdown.utf8), format: .markdown, fileName: "draft.md")

    #expect(document.sections[0].blocks.count == 1)
    #expect(document.sections[0].blocks[0].style == .code)
    #expect(document.sections[0].blocks[0].text == "print(\"Heavy\")")
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

@Test func javascriptImportSupportsAlternateDeclarationShapes() throws {
    let document = EditorDocument.sample()
    let encoder = JSONEncoder()
    let json = String(decoding: try encoder.encode(document), as: UTF8.self)
    let script = """
    const prefix = { ready: true };
    let heavyDocument = \(json);
    console.log(prefix.ready);
    """

    let imported = try DocumentTranscoder().import(Data(script.utf8), format: .javascript, fileName: "heavy.js")

    #expect(imported == document)
}

@Test func htmlImportPreservesImageSources() throws {
    let html = """
    <section>
      <h2>Gallery</h2>
      <figure><img src="https://example.com/path/cover.png"></figure>
      <figure><img alt="Inline" src="data:image/png;base64,iVBORw0KGgo="></figure>
    </section>
    """

    let document = try DocumentTranscoder().import(Data(html.utf8), format: .html, fileName: "gallery.html")

    #expect(document.sections[0].blocks.count == 2)
    #expect(document.sections[0].blocks[0].image?.source == "https://example.com/path/cover.png")
    #expect(document.sections[0].blocks[0].image?.filename == "cover.png")
    #expect(document.sections[0].blocks[1].image?.filename == "Inline")
    #expect(document.sections[0].blocks[1].image?.format == .png)
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

@Test func promoteFirstParagraphProcessorOnlyPromotesLeadParagraph() {
    let document = EditorDocument(
        title: "Draft",
        sections: [
            ContentSection(
                title: "Intro",
                blocks: [
                    ContentBlock(style: .quote, text: "Quote"),
                    ContentBlock(style: .paragraph, text: ""),
                    ContentBlock(style: .paragraph, text: "Lead paragraph"),
                    ContentBlock(style: .paragraph, text: "Body paragraph"),
                ]
            )
        ]
    )

    let processed = PromoteFirstParagraphProcessor().process(document: document)

    #expect(processed.sections[0].blocks[0].style == .quote)
    #expect(processed.sections[0].blocks[1].style == .paragraph)
    #expect(processed.sections[0].blocks[2].style == .heading)
    #expect(processed.sections[0].blocks[3].style == .paragraph)
}
