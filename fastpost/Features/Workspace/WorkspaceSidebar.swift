import AppKit
import SwiftUI

struct WorkspaceSidebar: View {
    @Environment(AppSession.self) private var session
    @State private var isFileDropTargeted = false

    var body: some View {
        @Bindable var session = session

        List(selection: $session.selectedItemID) {
            SidebarItemGroup(items: session.collectionItems)
        }
        .listStyle(.sidebar)
        .appThemeSidebar()
        .navigationTitle(session.currentWorkspace?.name ?? "Fastpost")
        .dropDestination(for: CollectionItemID.self) { ids, _ in
            guard let id = ids.first else { return false }
            return session.moveToRoot(id: id.rawValue)
        }
        .overlay {
            if session.collectionItems.isEmpty, session.renamingItemID == nil {
                ContentUnavailableView(
                    "No Requests",
                    systemImage: "tray",
                    description: Text("Create a folder or request, or drop a Postman collection to import.")
                )
                .allowsHitTesting(false)
            }
        }
        .overlay {
            SidebarFileDropCatcher(isTargeted: $isFileDropTargeted) { urls in
                _ = session.importPostmanFiles(urls)
            }
            .id("sidebar-file-drop-catcher")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .padding(6)
                .opacity(isFileDropTargeted ? 1 : 0)
                .allowsHitTesting(false)
                .animation(.smooth(duration: 0.12), value: isFileDropTargeted)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter()
        }
        .contextMenu {
            Button("New Request", systemImage: "plus") { session.beginCreate(.request) }
            Button("New Folder", systemImage: "folder.badge.plus") { session.beginCreate(.folder) }
            Button("Import…", systemImage: AppCommandCatalog[.importPostman].systemImage) {
                session.pickAndImportPostmanFiles()
            }
            if RequestPasteboard.hasRequest {
                Button("Paste Request", systemImage: AppCommandCatalog[.pasteRequest].systemImage) {
                    if let item = RequestPasteboard.peek() {
                        session.pasteRequest(item)
                    }
                }
            }
        }
        .onCopyCommand {
            guard let item = session.selectedItem, !item.isFolder else { return [] }
            RequestPasteboard.copy(item)
            return RequestPasteboard.itemProvider(for: item).map { [$0] } ?? []
        }
        .onPasteCommand(of: [RequestPasteboard.contentType]) { providers in
            RequestPasteboard.load(providers) { item in
                session.pasteRequest(item)
            }
        }
        .onKeyPress(.return) {
            guard session.renamingItemID == nil, session.selectedItemID != nil else {
                return .ignored
            }
            session.beginRename()
            return .handled
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: $session.isDeletePresented,
            presenting: session.pendingDeleteItem
        ) { _ in
            Button("Delete", role: .destructive) {
                session.confirmDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            if item.isFolder, item.childCount > 0 {
                Text("This folder and its contents will be removed from the collection.")
            } else {
                Text("This cannot be undone.")
            }
        }
    }

    private var deleteTitle: String {
        guard let item = session.pendingDeleteItem else {
            return String(localized: "Delete Item?")
        }
        return item.isFolder
            ? String(localized: "Delete Folder?")
            : String(localized: "Delete Request?")
    }
}

private struct SidebarItemGroup: View {
    let items: [CollectionItem]

    var body: some View {
        ForEach(items) { item in
            SidebarItemNode(item: item)
        }
    }
}

private struct SidebarItemNode: View {
    @Environment(AppSession.self) private var session
    let item: CollectionItem

    var body: some View {
        if item.isFolder {
            DisclosureGroup(isExpanded: expansion) {
                SidebarItemGroup(items: item.item ?? [])
            } label: {
                SidebarRow(
                    item: item,
                    isRenaming: session.renamingItemID == item.id
                )
                    .tag(item.id)
                    .onTapGesture(count: 2) {
                        session.toggleFolder(item.id)
                    }
            }
        } else {
            SidebarRow(
                item: item,
                isRenaming: session.renamingItemID == item.id
            )
                .tag(item.id)
        }
    }

    private var expansion: Binding<Bool> {
        Binding(
            get: { session.isFolderExpanded(item.id) },
            set: { isExpanded in
                if isExpanded {
                    session.expandFolder(item.id)
                } else if session.isFolderExpanded(item.id) {
                    session.toggleFolder(item.id)
                }
            }
        )
    }
}

struct SidebarRow: View {
    @Environment(AppSession.self) private var session
    @Environment(\.appTheme) private var theme
    let item: CollectionItem
    let isRenaming: Bool

    @State private var dropHint = SidebarDropHint.none
    @State private var draftName = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            rowIcon
            if isRenaming {
                TextField(item.defaultName, text: $draftName)
                    .textFieldStyle(.plain)
                    .focused($isNameFocused)
                    .onSubmit { session.finishRename(to: draftName) }
                    .onExitCommand { session.cancelRename() }
                    .onAppear {
                        draftName = item.name
                        isNameFocused = true
                        selectAllText()
                    }
                    .onChange(of: isNameFocused) { _, focused in
                        if !focused, session.renamingItemID == item.id {
                            session.finishRename(to: draftName)
                        }
                    }
            } else {
                Text(item.name.isEmpty ? item.defaultName : item.name)
                    .foregroundStyle(item.name.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 6)
        .help(item.name.isEmpty ? item.defaultName : item.name)
        .padding(.vertical, 2)
        .background { dropBackground }
        .overlay { dropOverlay }
        .contextMenu { rowContextMenu }
        .draggable(CollectionItemID(item.id)) {
            Label(item.name.isEmpty ? item.defaultName : item.name, systemImage: item.isFolder ? "folder" : "doc")
        }
        .dropDestination(for: CollectionItemID.self) { ids, location in
            performDrop(ids: ids, location: location)
        } isTargeted: { targeted in
            dropHint = targeted ? (item.isFolder ? .into : .after) : .none
        }
    }

    @ViewBuilder
    private var dropBackground: some View {
        if dropHint == .into {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.16))
        }
    }

    @ViewBuilder
    private var dropOverlay: some View {
        switch dropHint {
        case .none:
            EmptyView()
        case .into:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
        case .before:
            VStack {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                Spacer(minLength: 0)
            }
        case .after:
            VStack {
                Spacer(minLength: 0)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
    }

    private var rowIcon: some View {
        Group {
            if item.isFolder {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
            } else {
                Text(item.method?.rawValue ?? "GET")
                    .font(.caption2.weight(.semibold).monospaced())
                    .foregroundStyle(methodColor)
            }
        }
        .frame(minWidth: 28, alignment: .leading)
    }

    @ViewBuilder
    private var rowContextMenu: some View {
        Button("New Request", systemImage: "plus") {
            session.beginCreate(.request, relativeTo: item)
        }
        Button("New Folder", systemImage: "folder.badge.plus") {
            session.beginCreate(.folder, relativeTo: item)
        }
        Divider()
        if !item.isFolder {
            Button("Duplicate", systemImage: AppCommandCatalog[.duplicateRequest].systemImage) {
                session.duplicateRequest(id: item.id)
            }
            Button("Copy Request", systemImage: AppCommandCatalog[.copyRequest].systemImage) {
                RequestPasteboard.copy(item)
            }
            Button("Copy as cURL", systemImage: AppCommandCatalog[.copyAsCurl].systemImage) {
                session.copyAsCurl(id: item.id)
            }
        }
        if RequestPasteboard.hasRequest {
            Button("Paste Request", systemImage: AppCommandCatalog[.pasteRequest].systemImage) {
                if let payload = RequestPasteboard.peek() {
                    session.pasteRequest(payload, relativeTo: item)
                }
            }
        }
        Divider()
        Button("Rename", systemImage: "pencil") {
            session.beginRename(id: item.id)
        }
        Button("Delete…", systemImage: "trash", role: .destructive) {
            session.requestDelete(id: item.id)
        }
    }

    private var methodColor: Color {
        theme.method.color(for: item.method ?? .get)
    }

    private func performDrop(ids: [CollectionItemID], location: CGPoint) -> Bool {
        guard let dragged = ids.first, session.canMove(id: dragged.rawValue, onto: item) else {
            return false
        }
        if item.isFolder, location.y > 7, location.y < 18 {
            return session.move(id: dragged.rawValue, onto: item)
        }
        if location.y < 11 {
            return session.move(id: dragged.rawValue, before: item)
        }
        if item.isFolder {
            return session.move(id: dragged.rawValue, onto: item)
        }
        return session.move(id: dragged.rawValue, onto: item)
    }

    private func selectAllText() {
        DispatchQueue.main.async {
            (NSApp.keyWindow?.firstResponder as? NSText)?.selectAll(nil)
        }
    }
}

private enum SidebarDropHint: Equatable {
    case none
    case into
    case before
    case after
}

private struct SidebarFooter: View {
    @Environment(AppSession.self) private var session
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Button {
                session.beginCreate(.folder)
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            .help("New Folder")

            Button {
                session.beginCreate(.request)
            } label: {
                Label("New Request", systemImage: "plus")
            }
            .help("New Request")

            Spacer(minLength: 0)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(10)
        .background(theme.chrome?.sidebar ?? Color.clear)
    }
}

#Preview {
    NavigationSplitView {
        WorkspaceSidebar()
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
    } detail: {
        Text("Detail")
    }
    .environment(AppSession.preview)
    .frame(width: 800, height: 500)
}
