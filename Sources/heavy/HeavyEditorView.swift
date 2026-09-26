import Foundation
import HeavyCore

#if os(macOS)
import AppKit
import SwiftUI

struct HeavyEditorView: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle(store.document.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Import", action: store.importDocument)
                Picker("Export", selection: $store.selectedFormat) {
                    ForEach(ContentFormat.allCases, id: \.self) { format in
                        Text(format.rawValue.uppercased()).tag(format)
                    }
                }
                .frame(minWidth: 120)
                Button("Export", action: store.exportDocument)
                Button("Run Skill", action: store.runSelectedSkill)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let lastExportURL = store.lastExportURL {
                Label(lastExportURL.lastPathComponent, systemImage: "checkmark.circle.fill")
                    .padding(10)
                    .background(.thinMaterial, in: Capsule())
                    .padding()
            }
        }
        .alert("Heavy", isPresented: Binding(
            get: { store.lastErrorMessage != nil },
            set: { if !$0 { store.lastErrorMessage = nil } }
        ), actions: {
            Button("OK") { store.lastErrorMessage = nil }
        }, message: {
            Text(store.lastErrorMessage ?? "")
        })
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Document title", text: Binding(
                get: { store.document.title },
                set: {
                    store.document.title = $0
                    store.document.touch()
                }
            ))
            .textFieldStyle(.roundedBorder)

            Text("Sections")
                .font(.headline)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(store.document.sections) { section in
                        Button {
                            store.selectedSectionID = section.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(section.title.isEmpty ? "Untitled Section" : section.title)
                                        .font(.headline)
                                    Text("\(section.blocks.count) blocks")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding()
                            .background(store.selectedSectionID == section.id ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(section.title.isEmpty ? "Untitled Section" : section.title)
                        .draggable(DragPayload.section(section.id).rawValue)
                        .dropDestination(for: String.self) { items, _ in
                            guard let item = items.first else { return false }
                            store.moveSection(payload: item, before: section.id)
                            return true
                        }
                    }
                }
            }

            Button(action: store.addSection) {
                Label("Add Section", systemImage: "plus")
            }

            Divider()

            aiPanel
        }
        .padding()
        .frame(minWidth: 280)
    }

    private var aiPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI & MCP")
                .font(.headline)
            Toggle("Enable AI", isOn: Binding(
                get: { store.document.aiConfiguration.isEnabled },
                set: {
                    store.document.aiConfiguration.isEnabled = $0
                    store.document.touch()
                }
            ))
            TextField("Model", text: Binding(
                get: { store.document.aiConfiguration.preferredModel },
                set: {
                    store.document.aiConfiguration.preferredModel = $0
                    store.document.touch()
                }
            ))
            .textFieldStyle(.roundedBorder)
            Toggle("Enable MCP", isOn: Binding(
                get: { store.document.aiConfiguration.mcp.isEnabled },
                set: {
                    store.document.aiConfiguration.mcp.isEnabled = $0
                    store.document.touch()
                }
            ))
            TextField("MCP endpoint", text: Binding(
                get: { store.document.aiConfiguration.mcp.endpoint },
                set: {
                    store.document.aiConfiguration.mcp.endpoint = $0
                    store.document.touch()
                }
            ))
            .textFieldStyle(.roundedBorder)
            Picker("Skill", selection: $store.selectedSkillName) {
                if store.availableSkills.isEmpty {
                    Text("No skills available").tag("")
                } else {
                    ForEach(store.availableSkills) { skill in
                        Text(skill.name).tag(skill.name)
                    }
                }
            }
            .pickerStyle(.menu)
            .disabled(store.availableSkills.isEmpty)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedSectionID = store.selectedSectionID,
           let sectionIndex = store.document.sections.firstIndex(where: { $0.id == selectedSectionID }) {
            SectionEditorView(store: store, section: store.document.sections[sectionIndex])
        } else {
            ContentUnavailableView("Select a section", systemImage: "square.stack.3d.up")
        }
    }
}

private struct SectionEditorView: View {
    @ObservedObject var store: EditorStore
    let section: ContentSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Section title", text: Binding(
                    get: { section.title },
                    set: { store.updateSectionTitle($0, sectionID: section.id) }
                ))
                .font(.largeTitle.weight(.semibold))
                .textFieldStyle(.plain)

                blockPalette

                VStack(spacing: 12) {
                    ForEach(section.blocks) { block in
                        BlockCard(store: store, sectionID: section.id, block: block)
                            .draggable(DragPayload.block(section.id, block.id).rawValue)
                            .dropDestination(for: String.self) { items, _ in
                                guard let item = items.first else { return false }
                                store.moveBlock(payload: item, into: section.id, before: block.id)
                                return true
                            }
                    }
                }

                dropZone
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var blockPalette: some View {
        HStack {
            ForEach([BlockStyle.paragraph, .heading, .quote, .checklist, .code], id: \.self) { style in
                Button(style.rawValue.capitalized) {
                    store.addBlock(style: style, to: section.id)
                }
                .buttonStyle(.bordered)
            }

            Button("Image") { store.embedImage(into: section.id) }
                .buttonStyle(.borderedProminent)
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [8]))
            .foregroundStyle(.secondary)
            .frame(height: 72)
            .overlay(Text("Drop blocks here to append"))
            .accessibilityLabel("Append block drop target")
            .accessibilityValue("Drops dragged blocks at the end of this section")
            .dropDestination(for: String.self) { items, _ in
                guard let item = items.first else { return false }
                store.moveBlock(payload: item, into: section.id, before: nil)
                return true
            }
    }
}

private struct BlockCard: View {
    @ObservedObject var store: EditorStore
    let sectionID: UUID
    let block: ContentBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(block.style.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Move to End") {
                    store.moveBlockToEnd(sectionID: sectionID, blockID: block.id)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            switch block.style {
            case .heading:
                TextEditor(text: binding)
                    .font(.title3.weight(.semibold))
                    .frame(minHeight: 72)
            case .quote:
                TextEditor(text: binding)
                    .font(.body.italic())
                    .frame(minHeight: 88)
            case .checklist:
                Toggle(isOn: Binding(
                    get: { block.checked },
                    set: { store.toggleChecklist($0, sectionID: sectionID, blockID: block.id) }
                )) {
                    TextField("Checklist item", text: binding)
                }
            case .code:
                TextEditor(text: binding)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
            case .image:
                if let image = block.image,
                   let nsImage = NSImage(data: image.data),
                   !image.data.isEmpty {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 280)
                    Text(image.filename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let image = block.image, let source = image.source {
                    ContentUnavailableView("External image reference", systemImage: "photo.on.rectangle")
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("Embed a JPG or PNG", systemImage: "photo")
                }
            case .paragraph:
                TextEditor(text: binding)
                    .frame(minHeight: 120)
            }
        }
        .padding(18)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private var binding: Binding<String> {
        Binding(
            get: { block.text },
            set: { store.updateBlockText($0, sectionID: sectionID, blockID: block.id) }
        )
    }
}
#endif
