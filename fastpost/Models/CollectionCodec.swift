import Foundation

protocol CollectionCodec: Sendable {
    static func decode(from data: Data) throws -> Collection
    static func encode(_ collection: Collection) throws -> Data
}

enum PostmanCollectionCodec: CollectionCodec {
    static func decode(from data: Data) throws -> Collection {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Collection.self, from: data)
    }

    static func encode(_ collection: Collection) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(collection)
    }
}
