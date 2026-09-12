import Foundation

enum PostmanEnvironmentCodec {
    static func decode(from data: Data, fileName: String) throws -> WorkspaceEnvironment {
        let decoder = JSONDecoder()
        let file = try decoder.decode(PostmanEnvironmentFile.self, from: data)
        let id = UUID(uuidString: file.id) ?? UUID()
        let values = file.values.map { value in
            Variable(
                key: value.key,
                value: value.value ?? "",
                isEnabled: value.enabled ?? true,
                isSecret: value.type == "secret"
            )
        }
        return WorkspaceEnvironment(id: id, name: file.name, values: values, fileName: fileName)
    }

    static func encode(_ environment: WorkspaceEnvironment) throws -> Data {
        let file = PostmanEnvironmentFile(
            id: environment.id.uuidString,
            name: environment.name,
            values: environment.values.map { value in
                PostmanEnvironmentValue(
                    key: value.key,
                    value: value.value,
                    type: value.isSecret ? "secret" : "default",
                    enabled: value.isEnabled
                )
            },
            scope: "environment"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }
}

private struct PostmanEnvironmentFile: Codable {
    var id: String
    var name: String
    var values: [PostmanEnvironmentValue]
    var scope: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case values
        case scope = "_postman_variable_scope"
    }
}

private struct PostmanEnvironmentValue: Codable {
    var key: String
    var value: String?
    var type: String?
    var enabled: Bool?
}
