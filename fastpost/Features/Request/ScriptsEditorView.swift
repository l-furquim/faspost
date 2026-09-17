import SwiftUI

enum ScriptEditorMode: String, CaseIterable, Identifiable {
    case extract
    case script

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .extract: "Extract"
        case .script: "Script"
        }
    }

    var systemImage: String {
        switch self {
        case .extract: "tray.and.arrow.down"
        case .script: "chevron.left.forwardslash.chevron.right"
        }
    }
}

extension ScriptEditorMode: GlassSegmentOption {}

struct ScriptsEditorView: View {
    @Environment(AppSession.self) private var session
    let itemID: String
    @State private var mode = ScriptEditorMode.extract
    @State private var extractorRows: [ResponseExtractor] = []

    var body: some View {
        @Bindable var session = session

        VStack(alignment: .leading, spacing: 8) {
            GlassSegmentedPicker(selection: $mode, accessibilityLabel: "Scripts")

            Group {
                switch mode {
                case .extract:
                    extractorsTable
                case .script:
                    scriptEditor
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: reloadExtractors)
        .onChange(of: itemID) { _, _ in
            reloadExtractors()
        }
        .onChange(of: extractorRows) { _, newRows in
            if session.selectedExtractors != newRows {
                session.selectedExtractors = newRows
            }
        }
    }

    private var extractorsTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save values from the response into variables after Send.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach($extractorRows) { $row in
                ExtractorRowView(row: $row) {
                    extractorRows.removeAll { $0.id == row.id }
                }
            }

            Button("Add", systemImage: "plus") {
                extractorRows.append(ResponseExtractor())
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var scriptEditor: some View {
        @Bindable var session = session
        return VStack(alignment: .leading, spacing: 8) {
            Text("Postman-compatible JavaScript. Runs after Send. Use pm.response and pm.environment.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            CodeEditor(text: $session.selectedTestScript, language: .plain)
        }
    }

    private func reloadExtractors() {
        let incoming = session.selectedExtractors
        if incoming == extractorRows { return }
        extractorRows = incoming
    }
}

private struct ExtractorRowView: View {
    @Binding var row: ResponseExtractor
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("Enabled", isOn: $row.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help("Run this extractor")

            Picker("Source", selection: $row.source) {
                ForEach(ResponseExtractorSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .labelsHidden()
            .frame(width: 110)

            if row.source == .status {
                Text("Status code")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(row.source.pathPlaceholder, text: $row.path)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 140)
            }

            Picker("Save to", selection: $row.destination) {
                ForEach(ResponseExtractorDestination.allCases) { destination in
                    Text(destination.title).tag(destination)
                }
            }
            .labelsHidden()
            .frame(width: 130)

            TextField("Variable", text: $row.variableKey)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120)

            Button("Remove", systemImage: "minus.circle", role: .destructive, action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
    }
}

#Preview {
    ScriptsEditorView(itemID: "preview")
        .environment(AppSession.preview)
        .padding()
        .frame(width: 720, height: 280)
}
