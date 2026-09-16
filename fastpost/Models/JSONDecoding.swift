import Foundation

enum JSONFlexible {
    static func string<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> String? {
        guard container.contains(key), (try? container.decodeNil(forKey: key)) != true else {
            return nil
        }
        if let value = try? container.decode(String.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return String(value) }
        if let value = try? container.decode(Double.self, forKey: key) {
            return String(format: "%g", value)
        }
        if let value = try? container.decode(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        return nil
    }

    static func string(from container: SingleValueDecodingContainer) -> String? {
        if container.decodeNil() { return nil }
        if let value = try? container.decode(String.self) { return value }
        if let value = try? container.decode(Int.self) { return String(value) }
        if let value = try? container.decode(Double.self) { return String(format: "%g", value) }
        if let value = try? container.decode(Bool.self) { return value ? "true" : "false" }
        return nil
    }

    static func stringArray<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> [String]? {
        guard container.contains(key), (try? container.decodeNil(forKey: key)) != true else {
            return nil
        }
        if let values = try? container.decode([String].self, forKey: key) {
            return values
        }
        if let value = try? container.decode(String.self, forKey: key) {
            return value
                .split(separator: "/")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        guard var unkeyed = try? container.nestedUnkeyedContainer(forKey: key) else {
            return nil
        }
        var values: [String] = []
        while !unkeyed.isAtEnd {
            if let value = try? unkeyed.decode(String.self) {
                values.append(value)
            } else if let value = try? unkeyed.decode(Int.self) {
                values.append(String(value))
            } else {
                _ = try? unkeyed.decode(AnyJSON.self)
            }
        }
        return values
    }

    static func description<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> String? {
        if let value = string(from: container, forKey: key) { return value }
        if let object = try? container.decode(PostmanDescription.self, forKey: key) {
            return object.content
        }
        return nil
    }

    static func decodeMessage(_ error: Error) -> String {
        guard let error = error as? DecodingError else {
            return error.localizedDescription
        }
        switch error {
        case .typeMismatch(_, let context),
             .valueNotFound(_, let context),
             .keyNotFound(_, let context),
             .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).filter { !$0.isEmpty }.joined(separator: ".")
            if path.isEmpty { return context.debugDescription }
            return "\(context.debugDescription) (\(path))"
        @unknown default:
            return error.localizedDescription
        }
    }
}

struct LossyDecodableArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                _ = try container.decode(AnyJSON.self)
            }
        }
        self.elements = elements
    }
}

extension KeyedDecodingContainer {
    func decodeLossyArray<T: Decodable>(_ type: T.Type = T.self, forKey key: Key) -> [T] {
        decodeLossyArrayIfPresent(forKey: key) ?? []
    }

    func decodeLossyArrayIfPresent<T: Decodable>(_ type: T.Type = T.self, forKey key: Key) -> [T]? {
        guard contains(key), (try? decodeNil(forKey: key)) == false else { return nil }
        return try? decode(LossyDecodableArray<T>.self, forKey: key).elements
    }
}

private struct PostmanDescription: Decodable {
    var content: String?
}

enum AnyJSON: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: AnyJSON])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AnyJSON].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AnyJSON].self) {
            self = .object(value)
        } else {
            self = .null
        }
    }
}
