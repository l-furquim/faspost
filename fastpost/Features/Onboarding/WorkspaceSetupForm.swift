import SwiftUI

struct WorkspaceSetupForm: View {
    var confirmTitle: LocalizedStringKey = "Create Workspace"
    var onCreate: (String, URL) -> Void

    @State private var name = ""
    @State private var parentURL: URL?
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        !trimmedName.isEmpty && parentURL != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Workspace Name")
                    .font(.headline)
                TextField("Payments API", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit(createIfPossible)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Location")
                    .font(.headline)
                HStack(spacing: 10) {
                    locationLabel
                    Button("Choose…") {
                        isNameFocused = false
                        pickLocation()
                    }
                }
            }

            if let parentURL {
                Text(previewPath(parent: parentURL))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button(confirmTitle, action: createIfPossible)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canCreate)
        }
        .onAppear { isNameFocused = true }
    }

    private var locationLabel: some View {
        Label {
            Text(parentURL?.abbreviatedPath ?? String(localized: "No folder selected"))
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: "folder")
        }
        .foregroundStyle(parentURL == nil ? .secondary : .primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
    }

    private func pickLocation() {
        Task {
            guard let url = await FolderPicker.present(
                message: String(localized: "Choose the folder where this workspace will be created."),
                confirmTitle: String(localized: "Choose")
            ) else { return }
            parentURL = url
        }
    }

    private func createIfPossible() {
        guard canCreate, let parentURL else { return }
        onCreate(trimmedName, parentURL)
    }

    private func previewPath(parent: URL) -> String {
        let folder = WorkspaceStore.sanitizedFileName(trimmedName.isEmpty ? "Workspace" : trimmedName)
        return parent.appending(path: folder, directoryHint: .isDirectory).abbreviatedPath
    }
}

private extension URL {
    var abbreviatedPath: String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

#Preview("Setup Form") {
    WorkspaceSetupForm { _, _ in }
        .padding()
        .frame(width: 420)
}
