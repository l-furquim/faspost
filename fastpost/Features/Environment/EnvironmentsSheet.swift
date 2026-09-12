import AppKit
import SwiftUI

struct EnvironmentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @State private var selection: EnvironmentEditorTarget = .collection
    @State private var renamingID: UUID?
    @State private var pendingDeleteID: UUID?

    var body: some View {
        HSplitView {
            environmentList
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 320)
                .appThemeSidebar()

            EnvironmentEditorDetail(target: selection)
                .frame(minWidth: 560)
                .appThemeSurface()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Environments")
                    .font(.headline)
                Spacer(minLength: 0)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .appThemeBarBackground()
        }
        .frame(minWidth: 1040, minHeight: 720)
        .onKeyPress(.return) {
            guard renamingID == nil, case .environment(let id) = selection else {
                return .ignored
            }
            renamingID = id
            return .handled
        }
        .confirmationDialog(
            "Delete Environment?",
            isPresented: Binding(
                get: { pendingDeleteID != nil },
                set: { if !$0 { pendingDeleteID = nil } }
            ),
            presenting: pendingDeleteEnvironment
        ) { environment in
            Button("Delete", role: .destructive) {
                if selection == .environment(environment.id) {
                    selection = .collection
                }
                if renamingID == environment.id {
                    renamingID = nil
                }
                session.deleteEnvironment(id: environment.id)
                pendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteID = nil
            }
        } message: { environment in
            Text("“\(environment.name)” and its variables will be removed from this workspace.")
        }
    }

    private var environmentList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Label("Collection Variables", systemImage: "shippingbox")
                    .tag(EnvironmentEditorTarget.collection)

                Section("Environments") {
                    ForEach(session.environments) { environment in
                        EnvironmentListRow(
                            environment: environment,
                            isRenaming: renamingID == environment.id,
                            onFinishRename: { name in
                                session.renameEnvironment(id: environment.id, to: name)
                                renamingID = nil
                            },
                            onCancelRename: { renamingID = nil }
                        )
                        .tag(EnvironmentEditorTarget.environment(environment.id))
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") {
                                renamingID = environment.id
                            }
                            Button("Delete…", systemImage: "trash", role: .destructive) {
                                pendingDeleteID = environment.id
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)

            Divider()
            HStack {
                Button("New Environment", systemImage: "plus") {
                    let existing = Set(session.environments.map(\.id))
                    session.createEnvironment()
                    if let created = session.environments.first(where: { !existing.contains($0.id) }) {
                        selection = .environment(created.id)
                        renamingID = created.id
                    }
                }
                .help("New Environment")
                Spacer(minLength: 0)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(10)
        }
    }

    private var pendingDeleteEnvironment: WorkspaceEnvironment? {
        guard let pendingDeleteID else { return nil }
        return session.environments.first { $0.id == pendingDeleteID }
    }
}

private struct EnvironmentListRow: View {
    let environment: WorkspaceEnvironment
    let isRenaming: Bool
    var onFinishRename: (String) -> Void
    var onCancelRename: () -> Void

    @State private var draftName = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "server.rack")
                .foregroundStyle(.secondary)
            if isRenaming {
                TextField("New Environment", text: $draftName)
                    .textFieldStyle(.plain)
                    .focused($isNameFocused)
                    .onSubmit { finish() }
                    .onExitCommand { onCancelRename() }
                    .onAppear {
                        draftName = environment.name
                        isNameFocused = true
                        selectAllText()
                    }
                    .onChange(of: isNameFocused) { _, focused in
                        if !focused, isRenaming {
                            finish()
                        }
                    }
            } else {
                Text(environment.name)
                    .lineLimit(1)
            }
        }
    }

    private func finish() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        onFinishRename(trimmed.isEmpty ? environment.name : trimmed)
    }

    private func selectAllText() {
        DispatchQueue.main.async {
            (NSApp.keyWindow?.firstResponder as? NSText)?.selectAll(nil)
        }
    }
}

private struct EnvironmentEditorDetail: View {
    @Environment(AppSession.self) private var session
    let target: EnvironmentEditorTarget

    var body: some View {
        Form {
            switch target {
            case .collection:
                Section {
                    Text("Shared by every environment. Active environment values override these keys.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Collection Variables")
                }
                VariablesForm(variables: collectionBinding)
            case .environment(let id):
                if let environment = session.environments.first(where: { $0.id == id }) {
                    Section {
                        Text("Values here override collection variables with the same key.")
                            .foregroundStyle(.secondary)
                    } header: {
                        Text(environment.name)
                    }
                    VariablesForm(variables: environmentBinding(id))
                } else {
                    ContentUnavailableView(
                        "Environment Missing",
                        systemImage: "server.rack",
                        description: Text("Select another environment.")
                    )
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var collectionBinding: Binding<[Variable]> {
        Binding(
            get: { session.collectionVariables },
            set: { session.collectionVariables = $0 }
        )
    }

    private func environmentBinding(_ id: UUID) -> Binding<[Variable]> {
        Binding(
            get: { session.environments.first { $0.id == id }?.values ?? [] },
            set: { session.updateEnvironmentValues(id: id, $0) }
        )
    }
}

private struct VariablesForm: View {
    @Binding var variables: [Variable]

    var body: some View {
        Section("Variables") {
            ForEach($variables) { $variable in
                LabeledContent {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Key", text: $variable.key)
                        if variable.isSecret {
                            RevealableSecureField("Value", text: $variable.value)
                        } else {
                            TextField("Value", text: $variable.value)
                        }
                        HStack {
                            Toggle("Secret", isOn: $variable.isSecret)
                            Spacer(minLength: 0)
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                variables.removeAll { $0.id == variable.id }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                    }
                    .frame(maxWidth: 380, alignment: .leading)
                } label: {
                    Toggle("Enabled", isOn: $variable.isEnabled)
                }
            }

            Button("Add Variable", systemImage: "plus") {
                variables.append(Variable())
            }
        }
    }
}

#Preview {
    EnvironmentsSheet()
        .environment(AppSession.preview)
        .frame(width: 1040, height: 720)
}
