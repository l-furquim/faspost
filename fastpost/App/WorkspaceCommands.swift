import SwiftUI

struct WorkspaceCommands: Commands {
    @Bindable var session: AppSession
    @Bindable var runtime: RequestRuntime
    @Bindable var keybindings: KeybindingStore
    @FocusedBinding(\.isCommandPalettePresented) private var isCommandPalettePresented

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            commandButton(.newRequest) {
                session.beginCreate(.request)
            }
            .disabled(!session.hasOpenWorkspace)

            commandButton(.newFolder) {
                session.beginCreate(.folder)
            }
            .disabled(!session.hasOpenWorkspace)

            Divider()

            Button("New Workspace…") {
                session.present(.newWorkspace)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(!session.hasOpenWorkspace)

            Button("Open Workspace…") {
                session.pickAndOpenWorkspace()
            }
            .keyboardShortcut("o")

            commandButton(.importPostman) {
                session.pickAndImportPostmanFiles()
            }
            .disabled(!session.hasOpenWorkspace)
        }

        CommandGroup(after: .newItem) {
            Button(runtime.isSending(session.selectedItemID) ? "Stop Request" : "Send Request") {
                performer.perform(.send)
            }
            .appShortcut(.send, store: keybindings)
            .disabled(session.selectedRequest == nil)

            commandButton(.duplicateRequest) {
                session.duplicateRequest()
            }
            .disabled(session.selectedRequest == nil)

            Divider()

            commandButton(.rename) {
                session.beginRename()
            }
            .disabled(session.selectedItemID == nil || session.renamingItemID != nil)

            commandButton(.delete) {
                session.requestDelete()
            }
            .disabled(session.selectedItemID == nil)
        }

        CommandGroup(after: .pasteboard) {
            commandButton(.copyRequest) {
                performer.perform(.copyRequest)
            }
            .disabled(session.selectedRequest == nil)

            commandButton(.pasteRequest) {
                performer.perform(.pasteRequest)
            }
            .disabled(!session.hasOpenWorkspace || !RequestPasteboard.hasRequest)

            commandButton(.copyAsCurl) {
                session.copyAsCurl()
            }
            .disabled(session.selectedRequest == nil)
        }

        CommandMenu("Workspace") {
            if session.descriptors.isEmpty {
                Button("No Recent Workspaces") {}
                    .disabled(true)
            } else {
                ForEach(session.descriptors) { descriptor in
                    Button(descriptor.name) {
                        session.switchToDescriptor(descriptor)
                    }
                    .disabled(descriptor.id == session.currentWorkspace?.id)
                }
            }

            Divider()

            commandButton(.environments) {
                session.present(.environments)
            }
            .disabled(!session.hasOpenWorkspace)

            commandButton(.commandPalette) {
                isCommandPalettePresented = true
            }
            .disabled(isCommandPalettePresented == nil || !session.hasOpenWorkspace)
        }
    }

    private var performer: AppCommandPerformer {
        AppCommandPerformer(session: session, runtime: runtime)
    }

    private func commandButton(_ id: AppCommandID, action: @escaping () -> Void) -> some View {
        Button(AppCommandCatalog[id].title, action: action)
            .appShortcut(id, store: keybindings)
    }
}
