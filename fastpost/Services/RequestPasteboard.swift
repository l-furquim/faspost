import AppKit
import UniformTypeIdentifiers

enum RequestPasteboard {
    static let pasteboardType = NSPasteboard.PasteboardType("furqas.fastpost.request")
    static let contentType = UTType(exportedAs: "furqas.fastpost.request")

    static var hasRequest: Bool {
        NSPasteboard.general.data(forType: pasteboardType) != nil
    }

    static func copy(_ item: CollectionItem) {
        guard let data = encode(item) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: pasteboardType)
    }

    static func copyCurl(_ request: HTTPRequest) {
        let command: String
        if let urlRequest = try? HTTPClient(preferences: .current).makeURLRequest(from: request) {
            command = CurlExporter.command(from: urlRequest)
        } else {
            command = CurlExporter.command(from: request)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
    }

    static func peek() -> CollectionItem? {
        guard let data = NSPasteboard.general.data(forType: pasteboardType) else { return nil }
        return decode(data)
    }

    static func itemProvider(for item: CollectionItem) -> NSItemProvider? {
        guard let data = encode(item) else { return nil }
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: contentType.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    static func load(_ providers: [NSItemProvider], completion: @escaping (CollectionItem) -> Void) {
        let identifier = contentType.identifier
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(identifier) }) {
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                if let data, let item = decode(data) {
                    DispatchQueue.main.async { completion(item) }
                    return
                }
                if let item = peek() {
                    DispatchQueue.main.async { completion(item) }
                }
            }
            return
        }
        if let item = peek() {
            completion(item)
        }
    }

    private static func encode(_ item: CollectionItem) -> Data? {
        guard let request = item.request, !item.isFolder else { return nil }
        return try? JSONEncoder().encode(RequestClipboardPayload(name: item.displayName, request: request))
    }

    private static func decode(_ data: Data) -> CollectionItem? {
        guard let payload = try? JSONDecoder().decode(RequestClipboardPayload.self, from: data) else {
            return nil
        }
        return CollectionItem(name: payload.name, request: payload.request)
    }
}

private struct RequestClipboardPayload: Codable {
    var name: String
    var request: HTTPRequest
}
