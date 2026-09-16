import SwiftUI

enum AppCommandID: String, CaseIterable, Identifiable, Hashable {
    case newRequest
    case newFolder
    case importPostman
    case send
    case duplicateRequest
    case copyRequest
    case pasteRequest
    case copyAsCurl
    case rename
    case delete
    case environments
    case commandPalette

    var id: String { rawValue }
}

struct AppCommandDefinition: Identifiable, Equatable {
    var id: AppCommandID
    var title: LocalizedStringResource
    var systemImage: String
    var defaultKey: String?
    var defaultModifiers: EventModifiers = []

    var defaultBinding: Keybinding? {
        guard let defaultKey else { return nil }
        return Keybinding(key: defaultKey, modifiers: defaultModifiers)
    }
}

enum AppCommandCatalog {
    static let all: [AppCommandDefinition] = [
        AppCommandDefinition(id: .newRequest, title: "New Request", systemImage: "plus", defaultKey: "n", defaultModifiers: .command),
        AppCommandDefinition(id: .newFolder, title: "New Folder", systemImage: "folder.badge.plus", defaultKey: "n", defaultModifiers: [.command, .shift]),
        AppCommandDefinition(id: .importPostman, title: "Import…", systemImage: "square.and.arrow.down"),
        AppCommandDefinition(id: .send, title: "Send Request", systemImage: "paperplane", defaultKey: "return", defaultModifiers: .command),
        AppCommandDefinition(id: .duplicateRequest, title: "Duplicate", systemImage: "plus.square.on.square", defaultKey: "d", defaultModifiers: .command),
        AppCommandDefinition(id: .copyRequest, title: "Copy Request", systemImage: "doc.on.doc"),
        AppCommandDefinition(id: .pasteRequest, title: "Paste Request", systemImage: "doc.on.clipboard"),
        AppCommandDefinition(id: .copyAsCurl, title: "Copy as cURL", systemImage: "terminal", defaultKey: "c", defaultModifiers: [.command, .shift]),
        AppCommandDefinition(id: .rename, title: "Rename", systemImage: "pencil"),
        AppCommandDefinition(id: .delete, title: "Delete…", systemImage: "trash", defaultKey: "delete", defaultModifiers: .command),
        AppCommandDefinition(id: .environments, title: "Environments…", systemImage: "server.rack"),
        AppCommandDefinition(id: .commandPalette, title: "Commands", systemImage: "magnifyingglass", defaultKey: "k", defaultModifiers: .command),
    ]

    static var paletteCommands: [AppCommandDefinition] {
        all.filter { $0.id != .commandPalette }
    }

    static subscript(_ id: AppCommandID) -> AppCommandDefinition {
        all.first { $0.id == id } ?? AppCommandDefinition(id: id, title: "Command", systemImage: "app")
    }
}

struct AppCommandPerformer {
    var session: AppSession
    var runtime: RequestRuntime

    func perform(_ id: AppCommandID) {
        switch id {
        case .newRequest:
            session.beginCreate(.request)
        case .newFolder:
            session.beginCreate(.folder)
        case .importPostman:
            session.pickAndImportPostmanFiles()
        case .send:
            guard let itemID = session.selectedItemID, let request = session.selectedRequest else { return }
            runtime.toggleSend(id: itemID, request: session.resolved(request))
        case .duplicateRequest:
            session.duplicateRequest()
        case .copyRequest:
            guard let item = session.selectedItem else { return }
            RequestPasteboard.copy(item)
        case .pasteRequest:
            guard let item = RequestPasteboard.peek() else { return }
            session.pasteRequest(item)
        case .copyAsCurl:
            session.copyAsCurl()
        case .rename:
            session.beginRename()
        case .delete:
            session.requestDelete()
        case .environments:
            session.present(.environments)
        case .commandPalette:
            break
        }
    }

    func isEnabled(_ id: AppCommandID) -> Bool {
        switch id {
        case .newRequest, .newFolder, .importPostman, .environments, .commandPalette:
            session.hasOpenWorkspace
        case .send, .duplicateRequest, .copyRequest, .copyAsCurl:
            session.selectedRequest != nil
        case .pasteRequest:
            session.hasOpenWorkspace && RequestPasteboard.hasRequest
        case .rename, .delete:
            session.selectedItemID != nil && session.renamingItemID == nil
        }
    }
}

struct AppShortcutModifier: ViewModifier {
    @Environment(KeybindingStore.self) private var keybindings
    let id: AppCommandID

    func body(content: Content) -> some View {
        if let shortcut = keybindings.keyboardShortcut(for: id) {
            content.keyboardShortcut(shortcut)
        } else {
            content
        }
    }
}

extension View {
    func appShortcut(_ id: AppCommandID) -> some View {
        modifier(AppShortcutModifier(id: id))
    }

    @ViewBuilder
    func appShortcut(_ id: AppCommandID, store: KeybindingStore) -> some View {
        if let shortcut = store.keyboardShortcut(for: id) {
            keyboardShortcut(shortcut)
        } else {
            self
        }
    }
}

extension FocusedValues {
    @Entry var isCommandPalettePresented: Binding<Bool>?
}
