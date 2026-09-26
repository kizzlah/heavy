# heavy

Heavy is a Swift-based macOS writing app with a block editor designed for long-form drafting.

## Features

- Block-based writing surface with sections, headings, quotes, checklists, code blocks, and embedded images
- Drag-and-drop reordering for both sections and individual blocks
- Import and export support for Markdown, TXT, RTF, PDF, HTML, and JavaScript document payloads
- Optional AI settings with advanced skill selection and Modular Content Processing (MCP) hooks
- JPG and PNG image embedding for richer documents

## Package layout

- `/home/runner/work/heavy/heavy/Sources/HeavyCore`: shared document model, format transcoding, and MCP pipeline
- `/home/runner/work/heavy/heavy/Sources/heavy`: macOS SwiftUI app entry point and editor UI
- `/home/runner/work/heavy/heavy/Tests/HeavyCoreTests`: core behavior tests

## Development

```bash
swift build
swift test
```

Build and run the editor on macOS to launch the SwiftUI application.
