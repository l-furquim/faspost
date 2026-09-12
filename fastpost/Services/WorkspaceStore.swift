import Foundation

struct WorkspaceStore {
    private let defaults: UserDefaults
    private let registryKey = "workspaceRegistry"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadRegistry() -> WorkspaceRegistry {
        guard let data = defaults.data(forKey: registryKey) else {
            return .empty
        }
        do {
            return try JSONDecoder().decode(WorkspaceRegistry.self, from: data)
        } catch {
            return .empty
        }
    }

    func saveRegistry(_ registry: WorkspaceRegistry) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(registry) else { return }
        defaults.set(data, forKey: registryKey)
    }

    func createWorkspace(name: String, parentURL: URL) throws -> OpenedWorkspace {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw WorkspaceError.nameEmpty }

        return try withSecurityScopedAccess(to: parentURL) {
            let folderName = Self.sanitizedFileName(trimmedName)
            let rootURL = parentURL.appending(path: folderName, directoryHint: .isDirectory)

            if FileManager.default.fileExists(atPath: rootURL.path) {
                throw WorkspaceError.alreadyExists
            }

            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

            let collectionFileName = "\(folderName).postman_collection.json"
            let workspace = Workspace(
                id: UUID(),
                name: trimmedName,
                createdAt: .now,
                collectionFileName: collectionFileName
            )
            let collection = Collection.empty(named: trimmedName)

            try writeJSON(workspace, to: rootURL.appending(path: "workspace.json"))
            try saveCollection(collection, in: rootURL, fileName: collectionFileName)

            let bookmark = try makeBookmark(for: rootURL)
            return OpenedWorkspace(
                workspace: workspace,
                rootURL: rootURL,
                bookmark: bookmark,
                collection: collection,
                environments: []
            )
        }
    }

    func openWorkspace(at url: URL) throws -> OpenedWorkspace {
        return try withSecurityScopedAccess(to: url) {
            var workspace = try loadOrSynthesizeWorkspace(at: url)
            let collectionURL = url.appending(path: workspace.collectionFileName)
            let collection: Collection

            if FileManager.default.fileExists(atPath: collectionURL.path) {
                collection = try loadCollection(from: collectionURL)
            } else if let fallback = try findCollectionFile(in: url) {
                collection = try loadCollection(from: fallback)
                workspace.collectionFileName = fallback.lastPathComponent
            } else {
                throw WorkspaceError.invalidWorkspace
            }

            let environments = loadEnvironments(in: url)
            if let activeID = workspace.activeEnvironmentID,
               !environments.contains(where: { $0.id == activeID }) {
                workspace.activeEnvironmentID = nil
            }

            let bookmark = try makeBookmark(for: url)
            return OpenedWorkspace(
                workspace: workspace,
                rootURL: url,
                bookmark: bookmark,
                collection: collection,
                environments: environments
            )
        }
    }

    func resolveBookmark(_ data: Data) throws -> (url: URL, bookmark: Data, isStale: Bool) {
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw WorkspaceError.bookmarkFailed
        }
        return (url, data, isStale)
    }

    func refreshBookmark(for url: URL, current: Data) -> Data {
        (try? makeBookmark(for: url)) ?? current
    }

    func loadOpenedWorkspace(from descriptor: WorkspaceDescriptor) throws -> OpenedWorkspace {
        let resolved = try resolveBookmark(descriptor.bookmarkData)
        guard resolved.url.startAccessingSecurityScopedResource() else {
            throw WorkspaceError.accessDenied
        }
        defer { resolved.url.stopAccessingSecurityScopedResource() }

        guard FileManager.default.fileExists(atPath: resolved.url.path) else {
            throw WorkspaceError.folderMissing
        }

        var opened = try openWorkspace(at: resolved.url)
        opened.bookmark = resolved.isStale
            ? refreshBookmark(for: resolved.url, current: resolved.bookmark)
            : resolved.bookmark
        return opened
    }

    func saveWorkspace(_ workspace: Workspace, in rootURL: URL) throws {
        try writeJSON(workspace, to: rootURL.appending(path: "workspace.json"))
    }

    func loadEnvironments(in rootURL: URL) -> [WorkspaceEnvironment] {
        guard let urls = try? environmentFileURLs(in: rootURL) else { return [] }
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? PostmanEnvironmentCodec.decode(from: data, fileName: url.lastPathComponent)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func syncEnvironmentFiles(_ environments: [WorkspaceEnvironment], in rootURL: URL) throws {
        let wanted = Set(environments.map(\.fileName))
        for environment in environments {
            let url = rootURL.appending(path: environment.fileName)
            try PostmanEnvironmentCodec.encode(environment).write(to: url, options: .atomic)
        }
        for fileURL in try environmentFileURLs(in: rootURL) where !wanted.contains(fileURL.lastPathComponent) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func environmentFileURLs(in rootURL: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.lastPathComponent.hasSuffix(".postman_environment.json") }
    }

    private func loadOrSynthesizeWorkspace(at url: URL) throws -> Workspace {
        let metadataURL = url.appending(path: "workspace.json")
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            return try decodeJSON(Workspace.self, from: metadataURL)
        }

        guard let collectionURL = try findCollectionFile(in: url) else {
            throw WorkspaceError.invalidWorkspace
        }

        let collection = try loadCollection(from: collectionURL)
        let workspace = Workspace(
            id: UUID(),
            name: collection.info.name,
            createdAt: .now,
            collectionFileName: collectionURL.lastPathComponent
        )
        try writeJSON(workspace, to: metadataURL)
        return workspace
    }

    private func findCollectionFile(in url: URL) throws -> URL? {
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return contents.first { $0.lastPathComponent.hasSuffix(".postman_collection.json") }
            ?? contents.first {
                $0.pathExtension == "json"
                    && $0.lastPathComponent != "workspace.json"
                    && !$0.lastPathComponent.hasSuffix(".postman_environment.json")
            }
    }

    private func makeBookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw WorkspaceError.bookmarkFailed
        }
    }

    func saveCollection(_ collection: Collection, in rootURL: URL, fileName: String) throws {
        let url = rootURL.appending(path: fileName)
        try PostmanCollectionCodec.encode(collection).write(to: url, options: .atomic)
    }

    func loadCollection(from url: URL) throws -> Collection {
        try PostmanCollectionCodec.decode(from: Data(contentsOf: url))
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL, pretty: Bool = false) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        }
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    private func withSecurityScopedAccess<T>(to url: URL, perform: () throws -> T) throws -> T {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard didAccess || FileManager.default.isWritableFile(atPath: url.path) else {
            throw WorkspaceError.accessDenied
        }
        return try perform()
    }

    static func sanitizedFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name.unicodeScalars.map { scalar -> Character in
            invalid.contains(scalar) ? "-" : Character(scalar)
        }
        let trimmed = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Workspace" : trimmed
    }
}
