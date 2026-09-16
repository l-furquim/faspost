import Foundation

struct Workspace: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var collectionFileName: String
    var activeEnvironmentID: UUID?
}

struct WorkspaceDescriptor: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var bookmarkData: Data
    var lastOpenedAt: Date
}

struct WorkspaceRegistry: Codable, Equatable {
    var descriptors: [WorkspaceDescriptor]
    var lastActiveID: UUID?

    static let empty = WorkspaceRegistry(descriptors: [], lastActiveID: nil)
}

enum HTTPMethod: String, CaseIterable, Identifiable, Equatable, Hashable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
    case options = "OPTIONS"

    var id: String { rawValue }
}

enum WorkspaceError: LocalizedError, Equatable {
    case nameEmpty
    case accessDenied
    case alreadyExists
    case bookmarkFailed
    case invalidWorkspace
    case folderMissing
    case saveFailed
    case importFailed(String? = nil)

    var errorDescription: String? {
        switch self {
        case .nameEmpty:
            String(localized: "Enter a workspace name.")
        case .accessDenied:
            String(localized: "Fastpost could not access the selected folder.")
        case .alreadyExists:
            String(localized: "A workspace with this name already exists in that folder.")
        case .bookmarkFailed:
            String(localized: "Fastpost could not remember this folder. Choose it again.")
        case .invalidWorkspace:
            String(localized: "This folder is not a Fastpost workspace or a Postman collection.")
        case .folderMissing:
            String(localized: "This workspace folder is no longer available.")
        case .saveFailed:
            String(localized: "Fastpost could not save this collection.")
        case .importFailed(let detail):
            if let detail, !detail.isEmpty {
                String(localized: "This file is not a Postman collection or environment. \(detail)")
            } else {
                String(localized: "This file is not a Postman collection or environment.")
            }
        }
    }
}

enum WorkspaceSheet: Identifiable, Equatable, Hashable {
    case newWorkspace
    case environments

    var id: String {
        switch self {
        case .newWorkspace: "newWorkspace"
        case .environments: "environments"
        }
    }
}
