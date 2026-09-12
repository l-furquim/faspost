import Foundation

enum PersistenceStyle: Equatable {
    case immediate
    case debounced
}

@Observable
final class AppSession {
    var descriptors: [WorkspaceDescriptor]
    var currentWorkspace: Workspace?
    var collection: Collection?
    var environments: [WorkspaceEnvironment] = []
    var selectedItemID: CollectionItem.ID?
    var renamingItemID: CollectionItem.ID?
    var pendingDeleteID: CollectionItem.ID?
    var presentedSheet: WorkspaceSheet?
    var lastError: WorkspaceError?
    var expandedFolderIDs: Set<String> = []

    @ObservationIgnored
    private var currentRootURL: URL?
    @ObservationIgnored
    private var isAccessingCurrentRoot = false
    @ObservationIgnored
    private var persistTask: Task<Void, Never>?
    @ObservationIgnored
    private var isCreatingItem = false
    private let store: WorkspaceStore

    var hasOpenWorkspace: Bool { currentWorkspace != nil }

    var collectionItems: [CollectionItem] {
        collection?.item ?? []
    }

    var selectedItem: CollectionItem? {
        guard let selectedItemID else { return nil }
        return collection?.item.firstItem(id: selectedItemID)
    }

    var selectedRequest: HTTPRequest? {
        selectedItem?.request
    }

    var selectedRequestMethod: HTTPMethod {
        get { selectedItem?.method ?? .get }
        set { updateSelectedRequest(method: newValue.rawValue) }
    }

    var selectedRequestURL: String {
        get { selectedRequest?.rawURL ?? "" }
        set { updateSelectedRequest { $0.rawURL = newValue } }
    }

    var selectedBodyMode: RequestBodyMode {
        get { selectedRequest?.body?.kind ?? .none }
        set {
            updateSelectedRequest { request in
                var body = request.body ?? RequestBody()
                guard body.kind != newValue else { return }
                body.kind = newValue
                request.body = body
            }
        }
    }

    var selectedBodyJSON: String {
        get { selectedRequest?.body?.raw ?? "" }
        set {
            updateSelectedRequest { request in
                var body = request.body ?? RequestBody(mode: RequestBodyMode.raw.rawValue)
                guard body.raw != newValue else { return }
                body.raw = newValue
                request.body = body
            }
        }
    }

    var selectedBodyForm: [QueryParam] {
        get { selectedRequest?.body?.urlencoded ?? [] }
        set {
            updateSelectedRequest { request in
                var body = request.body ?? RequestBody(mode: RequestBodyMode.urlencoded.rawValue)
                guard body.urlencoded != newValue else { return }
                body.urlencoded = newValue
                request.body = body
            }
        }
    }

    var selectedAuth: RequestAuth {
        get { selectedRequest?.auth ?? .none }
        set {
            updateSelectedRequest { request in
                request.auth = newValue.isNone ? nil : newValue
            }
        }
    }

    var selectedHeaders: [HTTPHeader] {
        get { selectedRequest?.header ?? [] }
        set { updateSelectedRequest { $0.header = newValue } }
    }

    var selectedQueryParams: [QueryParam] {
        get { selectedRequest?.queryParams ?? [] }
        set { updateSelectedRequest { $0.setQueryParams(newValue) } }
    }

    var activeEnvironmentID: UUID? {
        currentWorkspace?.activeEnvironmentID
    }

    var activeEnvironment: WorkspaceEnvironment? {
        guard let activeEnvironmentID else { return nil }
        return environments.first { $0.id == activeEnvironmentID }
    }

    var collectionVariables: [Variable] {
        get { collection?.variable ?? [] }
        set { commit(.debounced) { $0.variable = newValue } }
    }

    var variableResolver: VariableResolver {
        VariableResolver(
            environmentValues: activeEnvironment?.values ?? [],
            collectionValues: collectionVariables,
            environmentName: activeEnvironment?.name
        )
    }

    func resolved(_ request: HTTPRequest) -> HTTPRequest {
        request.resolved(using: variableResolver)
    }

    var insertionParentID: String? {
        parentID(forCreateRelativeTo: selectedItem)
    }

    var pendingDeleteItem: CollectionItem? {
        guard let pendingDeleteID else { return nil }
        return collection?.item.firstItem(id: pendingDeleteID)
    }

    var isDeletePresented: Bool {
        get { pendingDeleteID != nil }
        set { if !newValue { pendingDeleteID = nil } }
    }

    init(store: WorkspaceStore = WorkspaceStore()) {
        self.store = store
        let registry = store.loadRegistry()
        descriptors = registry.descriptors.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
        if let lastActiveID = registry.lastActiveID {
            try? switchTo(id: lastActiveID)
        }
    }

    func createWorkspace(name: String, parentURL: URL) {
        do {
            adopt(try store.createWorkspace(name: name, parentURL: parentURL))
        } catch let error as WorkspaceError {
            lastError = error
        } catch {
            lastError = .accessDenied
        }
    }

    func pickAndOpenWorkspace() {
        Task {
            guard let url = await FolderPicker.present(
                message: String(localized: "Choose a Fastpost workspace or a folder that contains a Postman collection."),
                confirmTitle: String(localized: "Open"),
                canCreateDirectories: false
            ) else { return }
            openWorkspace(at: url)
        }
    }

    func openWorkspace(at url: URL) {
        do {
            adopt(try store.openWorkspace(at: url))
        } catch let error as WorkspaceError {
            lastError = error
        } catch {
            lastError = .invalidWorkspace
        }
    }

    func switchTo(id: UUID) throws {
        guard let descriptor = descriptors.first(where: { $0.id == id }) else {
            throw WorkspaceError.folderMissing
        }
        persistNow()
        adopt(try store.loadOpenedWorkspace(from: descriptor))
    }

    func switchToDescriptor(_ descriptor: WorkspaceDescriptor) {
        do {
            try switchTo(id: descriptor.id)
        } catch let error as WorkspaceError {
            lastError = error
        } catch {
            lastError = .folderMissing
        }
    }

    func beginCreate(_ kind: CollectionItemKind, relativeTo item: CollectionItem? = nil) {
        guard hasOpenWorkspace else { return }
        finishRenameIfNeeded()

        let newItem: CollectionItem = switch kind {
        case .folder: .folder(named: "")
        case .request: .request(named: "")
        }
        let parentID = parentID(forCreateRelativeTo: item ?? selectedItem)

        commit(.immediate) { collection in
            _ = collection.item.insert(newItem, parentID: parentID)
        }
        selectedItemID = newItem.id
        renamingItemID = newItem.id
        isCreatingItem = true
        if newItem.isFolder {
            expandedFolderIDs.insert(newItem.id)
        }
        if let parentID {
            expandedFolderIDs.insert(parentID)
        }
    }

    func duplicateRequest(id: CollectionItem.ID? = nil) {
        guard hasOpenWorkspace else { return }
        finishRenameIfNeeded()
        guard let targetID = id ?? selectedItemID,
              let source = collection?.item.firstItem(id: targetID),
              let clone = source.copiedRequest(named: source.duplicateDisplayName),
              let placement = collection?.item.siblingIndex(of: targetID)
        else { return }

        commit(.immediate) { collection in
            _ = collection.item.insert(clone, parentID: placement.parentID, at: placement.index + 1)
        }
        selectedItemID = clone.id
        if let parentID = placement.parentID {
            expandedFolderIDs.insert(parentID)
        }
    }

    func pasteRequest(_ item: CollectionItem, relativeTo target: CollectionItem? = nil) {
        guard hasOpenWorkspace else { return }
        finishRenameIfNeeded()
        guard let clone = item.copiedRequest() else { return }
        let placement = pastePlacement(relativeTo: target ?? selectedItem)

        commit(.immediate) { collection in
            _ = collection.item.insert(clone, parentID: placement.parentID, at: placement.index)
        }
        selectedItemID = clone.id
        if let parentID = placement.parentID {
            expandedFolderIDs.insert(parentID)
        }
    }

    func copyAsCurl(id: CollectionItem.ID? = nil) {
        guard let item = id.flatMap({ collection?.item.firstItem(id: $0) }) ?? selectedItem,
              let request = item.request
        else { return }
        RequestPasteboard.copyCurl(resolved(request))
    }

    func revealItem(id: CollectionItem.ID) {
        var current = collection?.item.parentID(of: id)
        while let parentID = current {
            expandedFolderIDs.insert(parentID)
            current = collection?.item.parentID(of: parentID)
        }
        selectedItemID = id
    }

    func isFolderExpanded(_ id: String) -> Bool {
        expandedFolderIDs.contains(id)
    }

    func toggleFolder(_ id: String) {
        if expandedFolderIDs.contains(id) {
            expandedFolderIDs.remove(id)
        } else {
            expandedFolderIDs.insert(id)
        }
    }

    func expandFolder(_ id: String) {
        expandedFolderIDs.insert(id)
    }

    func expandAllFolders() {
        expandedFolderIDs = Set(collectionItems.folderIDs)
    }

    func beginRename(id: CollectionItem.ID? = nil) {
        guard let targetID = id ?? selectedItemID else { return }
        finishRenameIfNeeded()
        selectedItemID = targetID
        renamingItemID = targetID
        isCreatingItem = false
    }

    func finishRename(to name: String) {
        guard let renamingItemID else { return }
        let item = collection?.item.firstItem(id: renamingItemID)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? (item?.defaultName ?? "New Request") : trimmed
        commit(.immediate) { collection in
            _ = collection.item.rename(id: renamingItemID, to: finalName)
        }
        self.renamingItemID = nil
        isCreatingItem = false
    }

    func cancelRename() {
        guard let renamingItemID else { return }
        if isCreatingItem {
            commit(.immediate) { collection in
                _ = collection.item.remove(id: renamingItemID)
            }
            if selectedItemID == renamingItemID {
                selectedItemID = nil
            }
        }
        self.renamingItemID = nil
        isCreatingItem = false
    }

    func requestDelete(id: CollectionItem.ID? = nil) {
        guard let targetID = id ?? selectedItemID else { return }
        pendingDeleteID = targetID
    }

    func confirmDelete() {
        guard let pendingDeleteID else { return }
        let parentID = collection?.item.parentID(of: pendingDeleteID)
        commit(.immediate) { collection in
            _ = collection.item.remove(id: pendingDeleteID)
        }
        if selectedItemID == pendingDeleteID {
            selectedItemID = parentID
        }
        if renamingItemID == pendingDeleteID {
            renamingItemID = nil
            isCreatingItem = false
        }
        self.pendingDeleteID = nil
    }

    func move(id: String, onto target: CollectionItem) -> Bool {
        if id == target.id { return false }
        if target.isFolder {
            expandedFolderIDs.insert(target.id)
            return move(id: id, toParent: target.id, afterID: nil)
        }
        let parentID = collection?.item.parentID(of: target.id)
        return move(id: id, toParent: parentID, afterID: target.id)
    }

    func move(id: String, before target: CollectionItem) -> Bool {
        if id == target.id { return false }
        let parentID = collection?.item.parentID(of: target.id)
        let siblings = parentID.flatMap { collection?.item.firstItem(id: $0)?.item } ?? collectionItems
        guard let index = siblings.firstIndex(where: { $0.id == target.id }) else { return false }
        if index == 0 {
            return move(id: id, toParent: parentID, afterID: nil, atStart: true)
        }
        return move(id: id, toParent: parentID, afterID: siblings[index - 1].id)
    }

    func moveToRoot(id: String) -> Bool {
        move(id: id, toParent: nil, afterID: collectionItems.last(where: { $0.id != id })?.id)
    }

    func canMove(id: String, onto target: CollectionItem) -> Bool {
        if id == target.id { return false }
        if target.isFolder {
            return !collectionItems.isDescendant(target.id, of: id)
        }
        if let parentID = collection?.item.parentID(of: target.id) {
            return !collectionItems.isDescendant(parentID, of: id)
        }
        return true
    }

    @discardableResult
    func move(id: String, toParent parentID: String?, afterID: String?, atStart: Bool = false) -> Bool {
        var didMove = false
        commit(.immediate) { collection in
            didMove = collection.item.move(id: id, toParent: parentID, afterID: afterID, atStart: atStart)
        }
        if didMove, let parentID {
            expandedFolderIDs.insert(parentID)
        }
        return didMove
    }

    func present(_ sheet: WorkspaceSheet) {
        presentedSheet = sheet
    }

    func dismissError() {
        lastError = nil
    }

    func selectEnvironment(id: UUID?) {
        currentWorkspace?.activeEnvironmentID = id
        persist(.immediate)
    }

    func createEnvironment(named name: String = "New Environment") {
        let uniqueName = uniqueEnvironmentName(base: name)
        let environment = WorkspaceEnvironment(
            name: uniqueName,
            values: [Variable()],
            fileName: uniqueEnvironmentFileName(for: uniqueName)
        )
        environments.append(environment)
        environments.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if activeEnvironmentID == nil {
            currentWorkspace?.activeEnvironmentID = environment.id
        }
        persist(.immediate)
    }

    func renameEnvironment(id: UUID, to name: String) {
        guard let index = environments.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        environments[index].name = trimmed
        environments[index].fileName = uniqueEnvironmentFileName(for: trimmed, excluding: id)
        environments.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist(.immediate)
    }

    func deleteEnvironment(id: UUID) {
        environments.removeAll { $0.id == id }
        if activeEnvironmentID == id {
            currentWorkspace?.activeEnvironmentID = environments.first?.id
        }
        persist(.immediate)
    }

    func updateEnvironmentValues(id: UUID, _ values: [Variable], style: PersistenceStyle = .debounced) {
        guard let index = environments.firstIndex(where: { $0.id == id }) else { return }
        environments[index].values = values
        persist(style)
    }

    func setVariableValue(_ name: String, to value: String, origin: VariableOrigin?) {
        switch origin {
        case .environment:
            guard let environmentID = activeEnvironmentID,
                  let envIndex = environments.firstIndex(where: { $0.id == environmentID }),
                  let valueIndex = environments[envIndex].values.firstIndex(where: { $0.key == name })
            else { return }
            environments[envIndex].values[valueIndex].value = value
            persist(.debounced)
        case .collection:
            var variables = collectionVariables
            guard let index = variables.firstIndex(where: { $0.key == name }) else { return }
            variables[index].value = value
            collectionVariables = variables
        case nil:
            addVariable(name: name, value: value)
        }
    }

    func addVariable(name: String, value: String = "") {
        if let environmentID = activeEnvironmentID,
           let envIndex = environments.firstIndex(where: { $0.id == environmentID }) {
            if let existing = environments[envIndex].values.firstIndex(where: { $0.key == name }) {
                environments[envIndex].values[existing].value = value
                environments[envIndex].values[existing].isEnabled = true
            } else {
                environments[envIndex].values.append(Variable(key: name, value: value))
            }
            persist(.immediate)
            return
        }

        var variables = collectionVariables
        if let existing = variables.firstIndex(where: { $0.key == name }) {
            variables[existing].value = value
            variables[existing].isEnabled = true
        } else {
            variables.append(Variable(key: name, value: value))
        }
        commit(.immediate) { $0.variable = variables }
    }

    func updateSelectedRequest(_ transform: (inout HTTPRequest) -> Void) {
        guard let selectedItemID else { return }
        commit(.debounced) { collection in
            _ = collection.item.updateItem(id: selectedItemID) { item in
                guard var request = item.request else { return }
                transform(&request)
                item.request = request
            }
        }
    }

    private func updateSelectedRequest(method: String? = nil, url: String? = nil) {
        updateSelectedRequest { request in
            if let method {
                request.method = method
            }
            if let url {
                request.rawURL = url
            }
        }
    }

    private func parentID(forCreateRelativeTo item: CollectionItem?) -> String? {
        guard let item else { return nil }
        if item.isFolder { return item.id }
        return collection?.item.parentID(of: item.id)
    }

    private func pastePlacement(relativeTo target: CollectionItem?) -> (parentID: String?, index: Int?) {
        guard let target else { return (nil, nil) }
        if target.isFolder {
            return (target.id, nil)
        }
        guard let placement = collection?.item.siblingIndex(of: target.id) else {
            return (nil, nil)
        }
        return (placement.parentID, placement.index + 1)
    }

    private func finishRenameIfNeeded() {
        guard renamingItemID != nil else { return }
        if let item = collection?.item.firstItem(id: renamingItemID ?? "") {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            finishRename(to: name.isEmpty ? item.defaultName : name)
        } else {
            renamingItemID = nil
            isCreatingItem = false
        }
    }

    private func commit(_ style: PersistenceStyle, _ transform: (inout Collection) -> Void) {
        var collection = collection ?? .empty(named: currentWorkspace?.name ?? "Collection")
        transform(&collection)
        self.collection = collection
        persist(style)
    }

    private func persist(_ style: PersistenceStyle) {
        switch style {
        case .immediate:
            persistNow()
        case .debounced:
            schedulePersist()
        }
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            persistNow()
        }
    }

    private func persistNow() {
        persistTask?.cancel()
        persistTask = nil
        guard let collection,
              let currentRootURL,
              let workspace = currentWorkspace
        else { return }

        do {
            try store.saveCollection(collection, in: currentRootURL, fileName: workspace.collectionFileName)
            try store.saveWorkspace(workspace, in: currentRootURL)
            try store.syncEnvironmentFiles(environments, in: currentRootURL)
        } catch {
            lastError = .saveFailed
        }
    }

    private func uniqueEnvironmentName(base: String) -> String {
        var name = base
        var suffix = 2
        let existing = Set(environments.map(\.name))
        while existing.contains(name) {
            name = "\(base) \(suffix)"
            suffix += 1
        }
        return name
    }

    private func uniqueEnvironmentFileName(for name: String, excluding id: UUID? = nil) -> String {
        var fileName = WorkspaceEnvironment.fileName(for: name)
        var suffix = 2
        let existing = Set(environments.compactMap { environment in
            environment.id == id ? nil : environment.fileName
        })
        while existing.contains(fileName) {
            fileName = "\(WorkspaceStore.sanitizedFileName(name))-\(suffix).postman_environment.json"
            suffix += 1
        }
        return fileName
    }

    private func adopt(_ opened: OpenedWorkspace) {
        persistNow()
        releaseCurrentRoot()

        var bookmarkData = opened.bookmark
        var scopedURL = opened.rootURL
        if let resolved = try? store.resolveBookmark(opened.bookmark) {
            scopedURL = resolved.url
            if resolved.isStale {
                bookmarkData = store.refreshBookmark(for: resolved.url, current: opened.bookmark)
            }
        }
        isAccessingCurrentRoot = scopedURL.startAccessingSecurityScopedResource()
        currentRootURL = scopedURL
        currentWorkspace = opened.workspace
        collection = opened.collection
        environments = opened.environments
        expandAllFolders()
        selectedItemID = nil
        renamingItemID = nil
        pendingDeleteID = nil
        isCreatingItem = false
        presentedSheet = nil

        upsertDescriptor(
            WorkspaceDescriptor(
                id: opened.workspace.id,
                name: opened.workspace.name,
                bookmarkData: bookmarkData,
                lastOpenedAt: .now
            )
        )
        persistRegistry()
    }

    private func upsertDescriptor(_ descriptor: WorkspaceDescriptor) {
        if let index = descriptors.firstIndex(where: { $0.id == descriptor.id }) {
            descriptors[index] = descriptor
        } else {
            descriptors.append(descriptor)
        }
        descriptors.sort { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    private func persistRegistry() {
        store.saveRegistry(
            WorkspaceRegistry(
                descriptors: descriptors,
                lastActiveID: currentWorkspace?.id
            )
        )
    }

    private func releaseCurrentRoot() {
        if isAccessingCurrentRoot, let currentRootURL {
            currentRootURL.stopAccessingSecurityScopedResource()
        }
        currentRootURL = nil
        isAccessingCurrentRoot = false
    }
}

extension AppSession {
    static var preview: AppSession {
        let suiteName = "fastpost.preview"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let session = AppSession(store: WorkspaceStore(defaults: defaults))
        session.currentWorkspace = Workspace(
            id: UUID(),
            name: "Payments API",
            createdAt: .now,
            collectionFileName: "Payments API.postman_collection.json"
        )
        session.collection = Collection(
            info: CollectionInfo(
                postmanID: UUID().uuidString,
                name: "Payments API",
                schema: Collection.postmanV21Schema
            ),
            item: [
                CollectionItem(
                    name: "Customers",
                    item: [
                        CollectionItem.request(named: "List customers"),
                        CollectionItem(
                            name: "Create customer",
                            request: HTTPRequest(
                                method: "POST",
                                header: [],
                                url: .raw("https://api.example.com/customers")
                            )
                        ),
                    ]
                ),
                CollectionItem(
                    name: "Health",
                    request: HTTPRequest(
                        method: "GET",
                        header: [],
                        url: .raw("https://api.example.com/health")
                    )
                ),
            ]
        )
        session.collection?.variable = [
            Variable(key: "baseUrl", value: "https://api.example.com"),
        ]
        session.environments = [
            WorkspaceEnvironment(
                name: "Local",
                values: [Variable(key: "baseUrl", value: "http://localhost:3000")]
            ),
            WorkspaceEnvironment(
                name: "Production",
                values: [Variable(key: "baseUrl", value: "https://api.example.com")]
            ),
        ]
        session.currentWorkspace?.activeEnvironmentID = session.environments.first?.id
        session.selectedItemID = session.collection?.item.last?.id
        session.expandAllFolders()
        return session
    }

    static var previewEmpty: AppSession {
        let suiteName = "fastpost.preview.empty"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return AppSession(store: WorkspaceStore(defaults: defaults))
    }
}
