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
            .listStyle(.plain)

            Divider()
            HStack(spacing: 8) {
                Button("New Environment", systemImage: "plus") {
                    createEnvironment()
                }
                .help("New Environment")
                Button("Delete Environment", systemImage: "minus") {
                    if case .environment(let id) = selection {
                        pendingDeleteID = id
                    }
                }
                .help("Delete Environment")
                .disabled(!canDeleteSelection)
                Spacer(minLength: 0)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(10)
        }
    }

    private var canDeleteSelection: Bool {
        if case .environment = selection { return true }
        return false
    }

    private func createEnvironment() {
        let existing = Set(session.environments.map(\.id))
        session.createEnvironment()
        if let created = session.environments.first(where: { !existing.contains($0.id) }) {
            selection = .environment(created.id)
            renamingID = created.id
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
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            variables
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var header: some View {
        Form {
            switch target {
            case .collection:
                Section {
                    Text("Shared by every environment. Active environment values override these keys.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Collection Variables")
                }
            case .environment(let id):
                if let environment = session.environments.first(where: { $0.id == id }) {
                    Section {
                        Text("Values here override collection variables with the same key.")
                            .foregroundStyle(.secondary)
                    } header: {
                        Text(environment.name)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var variables: some View {
        switch target {
        case .collection:
            VariablesTable(variables: collectionBinding)
        case .environment(let id):
            if session.environments.contains(where: { $0.id == id }) {
                VariablesTable(variables: environmentBinding(id))
            } else {
                ContentUnavailableView(
                    "Environment Missing",
                    systemImage: "server.rack",
                    description: Text("Select another environment.")
                )
            }
        }
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

private struct VariablesTable: View {
    @Binding var variables: [Variable]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Variables")
                .font(.headline)
            ForEach($variables) { $variable in
                VariableRowView(variable: $variable) {
                    variables.removeAll { $0.id == variable.id }
                }
            }

            Button("Add Variable", systemImage: "plus") {
                variables.append(Variable())
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct VariableRowView: View {
    @Binding var variable: Variable
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("Enabled", isOn: $variable.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help("Include this variable")
            TextField("Key", text: $variable.key)
                .textFieldStyle(.roundedBorder)
            valueField
            Button(variable.isSecret ? "Make Visible" : "Make Secret", systemImage: variable.isSecret ? "lock.fill" : "lock.open") {
                variable.isSecret.toggle()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(variable.isSecret ? "Secret variable" : "Visible variable")
            Button("Remove", systemImage: "minus.circle", role: .destructive, action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var valueField: some View {
        if variable.isSecret {
            RevealableSecureField("Value", text: $variable.value, usesVariables: true, layout: .compact)
        } else {
            VariableTextField(text: $variable.value, placeholder: "Value")
        }
    }
}

#Preview {
    EnvironmentsSheet()
        .environment(AppSession.preview)
        .frame(width: 1040, height: 720)
}
