import Foundation

struct Variable: Identifiable, Equatable, Hashable {
    var id: String
    var key: String
    var value: String
    var isEnabled: Bool
    var isSecret: Bool

    init(
        id: String = UUID().uuidString,
        key: String = "",
        value: String = "",
        isEnabled: Bool = true,
        isSecret: Bool = false
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
        self.isSecret = isSecret
    }
}

extension Variable: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case key
        case value
        case type
        case disabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        let type = try container.decodeIfPresent(String.self, forKey: .type)
        isSecret = type == "secret"
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .disabled) != true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(key, forKey: .key)
        try container.encode(value, forKey: .value)
        try container.encode(isSecret ? "secret" : "string", forKey: .type)
        if !isEnabled {
            try container.encode(true, forKey: .disabled)
        }
    }
}

struct WorkspaceEnvironment: Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var values: [Variable]
    var fileName: String

    init(
        id: UUID = UUID(),
        name: String,
        values: [Variable] = [],
        fileName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.values = values
        self.fileName = fileName ?? Self.fileName(for: name)
    }

    static func named(_ name: String) -> WorkspaceEnvironment {
        WorkspaceEnvironment(name: name, values: [Variable()])
    }

    static func fileName(for name: String) -> String {
        "\(WorkspaceStore.sanitizedFileName(name)).postman_environment.json"
    }

    mutating func refreshFileName() {
        fileName = Self.fileName(for: name)
    }
}

struct OpenedWorkspace {
    var workspace: Workspace
    var rootURL: URL
    var bookmark: Data
    var collection: Collection
    var environments: [WorkspaceEnvironment]
}

enum VariableOrigin: Equatable, Hashable {
    case environment(name: String)
    case collection

    var title: String {
        switch self {
        case .environment(let name): name
        case .collection: "Collection"
        }
    }
}

struct VariableSuggestion: Identifiable, Equatable, Hashable {
    var key: String
    var value: String
    var origin: VariableOrigin

    var id: String { "\(origin.title):\(key)" }

    var insertion: String { "{{\(key)}}" }
}

struct IncompleteVariable: Equatable {
    var prefix: String
    var replacementRange: NSRange
}

struct VariableToken: Identifiable, Equatable, Hashable {
    var name: String
    var nsRange: NSRange
    var resolvedValue: String?
    var origin: VariableOrigin?

    var id: String { "\(name)@\(nsRange.location)" }
    var isResolved: Bool { resolvedValue != nil }
}

enum EnvironmentEditorTarget: Hashable, Identifiable {
    case collection
    case environment(UUID)

    var id: String {
        switch self {
        case .collection: "collection"
        case .environment(let id): id.uuidString
        }
    }
}
