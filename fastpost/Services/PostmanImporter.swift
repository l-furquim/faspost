import Foundation

enum PostmanImporter {
    enum Payload: Equatable {
        case collection(Collection)
        case environment(WorkspaceEnvironment)
    }

    static func payload(from data: Data, fileName: String) throws -> Payload {
        if looksLikeCollection(data) {
            do {
                return .collection(try PostmanCollectionCodec.decode(from: data))
            } catch {
                throw WorkspaceError.importFailed(JSONFlexible.decodeMessage(error))
            }
        }

        if looksLikeEnvironment(data) {
            do {
                return .environment(try PostmanEnvironmentCodec.decode(from: data, fileName: fileName))
            } catch {
                throw WorkspaceError.importFailed(JSONFlexible.decodeMessage(error))
            }
        }

        do {
            return .collection(try PostmanCollectionCodec.decode(from: data))
        } catch let collectionError {
            do {
                return .environment(try PostmanEnvironmentCodec.decode(from: data, fileName: fileName))
            } catch {
                throw WorkspaceError.importFailed(JSONFlexible.decodeMessage(collectionError))
            }
        }
    }

    static func importedFolder(from collection: Collection, named fallbackName: String) -> CollectionItem {
        CollectionItem(
            name: displayName(collection.info.name, fallback: fallbackName),
            item: collection.item.map(remintedItem),
            event: collection.event
        )
    }

    static func mergingVariables(existing: [Variable], imported: [Variable]) -> [Variable] {
        var merged = existing
        var seen = Set(
            existing
                .map { $0.key.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        for variable in imported {
            let key = variable.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            merged.append(
                Variable(
                    key: key,
                    value: variable.value,
                    isEnabled: variable.isEnabled,
                    isSecret: variable.isSecret
                )
            )
        }
        return merged
    }

    static func collectionFallbackName(from fileName: String) -> String {
        strippedFileName(
            fileName,
            suffixes: [".postman_collection.json", ".json"],
            fallback: "Imported Collection"
        )
    }

    static func environmentFallbackName(from fileName: String) -> String {
        strippedFileName(
            fileName,
            suffixes: [".postman_environment.json", ".json"],
            fallback: "Imported Environment"
        )
    }

    static func displayName(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let fallbackName = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallbackName.isEmpty ? "Imported Collection" : fallbackName
    }

    private static func looksLikeCollection(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = json["info"] as? [String: Any]
        else { return false }
        if let schema = info["schema"] as? String, schema.localizedCaseInsensitiveContains("collection") {
            return true
        }
        return info["name"] != nil
    }

    private static func looksLikeEnvironment(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if let scope = json["_postman_variable_scope"] as? String,
           scope.localizedCaseInsensitiveContains("environment") {
            return true
        }
        return json["values"] is [[String: Any]] && json["name"] is String && json["info"] == nil
    }

    private static func remintedItem(_ item: CollectionItem) -> CollectionItem {
        CollectionItem(
            name: item.name,
            item: item.item.map { $0.map(remintedItem) },
            request: item.request,
            event: item.event,
            responseExtractors: item.responseExtractors
        )
    }

    private static func strippedFileName(
        _ fileName: String,
        suffixes: [String],
        fallback: String
    ) -> String {
        var name = fileName
        for suffix in suffixes where name.lowercased().hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            break
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
