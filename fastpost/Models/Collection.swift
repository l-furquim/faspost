import Foundation
import CoreTransferable

struct Collection: Codable, Equatable, Hashable {
    var info: CollectionInfo
    var item: [CollectionItem]
    var variable: [Variable]

    static let postmanV21Schema = "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"

    enum CodingKeys: String, CodingKey {
        case info
        case item
        case variable
    }

    init(info: CollectionInfo, item: [CollectionItem], variable: [Variable] = []) {
        self.info = info
        self.item = item
        self.variable = variable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        info = try container.decode(CollectionInfo.self, forKey: .info)
        item = try container.decodeIfPresent([CollectionItem].self, forKey: .item) ?? []
        variable = try container.decodeIfPresent([Variable].self, forKey: .variable) ?? []
    }

    static func empty(named name: String) -> Collection {
        Collection(
            info: CollectionInfo(
                postmanID: UUID().uuidString,
                name: name,
                schema: postmanV21Schema
            ),
            item: []
        )
    }
}

struct CollectionInfo: Codable, Equatable, Hashable {
    var postmanID: String
    var name: String
    var schema: String
    var description: String?

    enum CodingKeys: String, CodingKey {
        case postmanID = "_postman_id"
        case name
        case schema
        case description
    }
}

struct CollectionItemID: Hashable, Codable, Sendable, Transferable {
    var rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.rawValue) { CollectionItemID($0) }
    }
}

struct CollectionItem: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var item: [CollectionItem]?
    var request: HTTPRequest?

    var isFolder: Bool { item != nil }

    var method: HTTPMethod? {
        guard let raw = request?.method else { return nil }
        return HTTPMethod(rawValue: raw.uppercased())
    }

    var defaultName: String {
        isFolder ? "New Folder" : "New Request"
    }

    var childCount: Int {
        item?.count ?? 0
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        item: [CollectionItem]? = nil,
        request: HTTPRequest? = nil
    ) {
        self.id = id
        self.name = name
        self.item = item
        self.request = request
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decode(String.self, forKey: .name)
        item = try container.decodeIfPresent([CollectionItem].self, forKey: .item)
        request = try container.decodeIfPresent(HTTPRequest.self, forKey: .request)
    }

    static func folder(named name: String) -> CollectionItem {
        CollectionItem(name: name, item: [])
    }

    static func request(named name: String, method: HTTPMethod = .get) -> CollectionItem {
        CollectionItem(
            name: name,
            request: HTTPRequest(method: method.rawValue, header: [], url: .raw(""))
        )
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultName : trimmed
    }

    var duplicateDisplayName: String {
        "\(displayName) Copy"
    }

    func copiedRequest(named name: String? = nil) -> CollectionItem? {
        guard let request, !isFolder else { return nil }
        return CollectionItem(name: name ?? displayName, request: request)
    }
}

struct HTTPRequest: Codable, Equatable, Hashable {
    var method: String
    var header: [HTTPHeader]
    var url: RequestURL
    var body: RequestBody?
    var auth: RequestAuth?
    var description: String?

    var rawURL: String {
        get { url.rawValue }
        set { url = .raw(newValue) }
    }

    var enabledHeaders: [HTTPHeader] {
        header.filter { $0.disabled != true && !$0.key.isEmpty }
    }

    var queryParams: [QueryParam] {
        if case .structured(let object) = url, let query = object.query {
            return query
        }
        return Self.parseQuery(from: rawURL)
    }

    mutating func setQueryParams(_ params: [QueryParam]) {
        let current = rawURL
        let base = current.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? current
        let enabled = params.filter { $0.disabled != true && !$0.key.isEmpty }
        let next: String
        if enabled.isEmpty {
            next = base
        } else {
            let query = enabled.map { param in
                "\(Self.encodeQueryComponent(param.key))=\(Self.encodeQueryComponent(param.value ?? ""))"
            }.joined(separator: "&")
            next = "\(base)?\(query)"
        }
        var object = RequestURLObject(raw: next)
        if case .structured(let existing) = url {
            object = existing
            object.raw = next
        }
        object.query = params
        url = .structured(object)
    }

    static func parseQuery(from rawURL: String) -> [QueryParam] {
        let candidate = rawURL.contains("://") ? rawURL : "https://\(rawURL)"
        guard let components = URLComponents(string: candidate) else { return [] }
        return (components.queryItems ?? []).map { QueryParam(key: $0.name, value: $0.value) }
    }

    private func normalizedURLString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return trimmed }
        if trimmed.contains("://") { return trimmed }
        return "https://\(trimmed)"
    }

    static func encodeQueryComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(charactersIn: "{}")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func restoreTemplateBraces(_ value: String) -> String {
        value
            .replacingOccurrences(of: "%7B", with: "{")
            .replacingOccurrences(of: "%7D", with: "}")
            .replacingOccurrences(of: "%7b", with: "{")
            .replacingOccurrences(of: "%7d", with: "}")
    }
}

struct HTTPHeader: Codable, Equatable, Hashable {
    var key: String
    var value: String
    var disabled: Bool?
}

struct QueryParam: Codable, Equatable, Hashable {
    var key: String
    var value: String?
    var disabled: Bool?
}

enum RequestBodyMode: String, CaseIterable, Identifiable, Equatable, Hashable {
    case none
    case raw
    case urlencoded

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .none: "No Body"
        case .raw: "JSON"
        case .urlencoded: "Form URL Encoded"
        }
    }

    var systemImage: String {
        switch self {
        case .none: "slash.circle"
        case .raw: "curlybraces"
        case .urlencoded: "list.bullet.rectangle"
        }
    }
}

struct RequestBody: Codable, Equatable, Hashable {
    var mode: String?
    var raw: String?
    var urlencoded: [QueryParam]?

    var kind: RequestBodyMode {
        get {
            if let mode, let parsed = RequestBodyMode(rawValue: mode) {
                return parsed
            }
            if raw?.isEmpty == false { return .raw }
            if urlencoded?.isEmpty == false { return .urlencoded }
            return .none
        }
        set { mode = newValue.rawValue }
    }

    var enabledFormFields: [QueryParam] {
        (urlencoded ?? []).filter { $0.disabled != true && !$0.key.isEmpty }
    }

    func encodedPayload() -> (data: Data, contentType: String)? {
        switch kind {
        case .none:
            return nil
        case .raw:
            guard let raw, !raw.isEmpty else { return nil }
            return (Data(raw.utf8), "application/json")
        case .urlencoded:
            let fields = enabledFormFields
            guard !fields.isEmpty else { return nil }
            let query = fields.map { field in
                "\(HTTPRequest.encodeQueryComponent(field.key))=\(HTTPRequest.encodeQueryComponent(field.value ?? ""))"
            }.joined(separator: "&")
            return (Data(query.utf8), "application/x-www-form-urlencoded")
        }
    }
}

struct RequestURLObject: Codable, Equatable, Hashable {
    var raw: String?
    var protocolName: String?
    var host: [String]?
    var path: [String]?
    var query: [QueryParam]?

    enum CodingKeys: String, CodingKey {
        case raw
        case protocolName = "protocol"
        case host
        case path
        case query
    }
}

enum RequestURL: Codable, Equatable, Hashable {
    case raw(String)
    case structured(RequestURLObject)

    var rawValue: String {
        switch self {
        case .raw(let string):
            HTTPRequest.restoreTemplateBraces(string)
        case .structured(let object):
            HTTPRequest.restoreTemplateBraces(object.raw ?? "")
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .raw(string)
            return
        }
        self = .structured(try container.decode(RequestURLObject.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .raw(let string):
            try container.encode(string)
        case .structured(let object):
            try container.encode(object)
        }
    }
}

enum CollectionItemKind: Equatable {
    case folder
    case request
}

extension [CollectionItem] {
    func firstItem(id: String) -> CollectionItem? {
        for item in self {
            if item.id == id { return item }
            if let match = item.item?.firstItem(id: id) {
                return match
            }
        }
        return nil
    }

    func containsItem(id: String) -> Bool {
        firstItem(id: id) != nil
    }

    func parentID(of id: String, parent: String? = nil) -> String? {
        for item in self {
            if item.id == id { return parent }
            if let nested = item.item, let found = nested.parentID(of: id, parent: item.id) {
                return found
            }
        }
        return nil
    }

    func isDescendant(_ candidateID: String?, of ancestorID: String) -> Bool {
        guard let candidateID else { return false }
        if candidateID == ancestorID { return true }
        return firstItem(id: ancestorID)?.item?.containsItem(id: candidateID) == true
    }

    var folderIDs: [String] {
        flatMap { item in
            guard item.isFolder else { return [String]() }
            return [item.id] + (item.item ?? []).folderIDs
        }
    }

    func siblingIndex(of id: String) -> (parentID: String?, index: Int)? {
        if let index = firstIndex(where: { $0.id == id }) {
            return (nil, index)
        }
        for item in self {
            guard let children = item.item else { continue }
            if let index = children.firstIndex(where: { $0.id == id }) {
                return (item.id, index)
            }
            if let nested = children.siblingIndex(of: id) {
                return nested
            }
        }
        return nil
    }

    func flattenedRequests(path: [String] = []) -> [(item: CollectionItem, path: [String])] {
        flatMap { item in
            if item.isFolder {
                return (item.item ?? []).flattenedRequests(path: path + [item.displayName])
            }
            return [(item, path)]
        }
    }

    mutating func insert(_ newItem: CollectionItem, parentID: String?, at index: Int? = nil) -> Bool {
        if parentID == nil {
            insert(newItem, at: clamped(index, count: count))
            return true
        }

        for itemIndex in indices {
            if self[itemIndex].id == parentID {
                if self[itemIndex].item == nil {
                    self[itemIndex].item = []
                }
                let children = self[itemIndex].item?.count ?? 0
                let insertionIndex = clamped(index, count: children)
                self[itemIndex].item?.insert(newItem, at: insertionIndex)
                return true
            }
            if self[itemIndex].item != nil, self[itemIndex].item!.insert(newItem, parentID: parentID, at: index) {
                return true
            }
        }
        return false
    }

    mutating func updateItem(id: String, transform: (inout CollectionItem) -> Void) -> Bool {
        for index in indices {
            if self[index].id == id {
                transform(&self[index])
                return true
            }
            if self[index].item != nil, self[index].item!.updateItem(id: id, transform: transform) {
                return true
            }
        }
        return false
    }

    mutating func rename(id: String, to name: String) -> Bool {
        updateItem(id: id) { $0.name = name }
    }

    @discardableResult
    mutating func remove(id: String) -> CollectionItem? {
        for index in indices {
            if self[index].id == id {
                return remove(at: index)
            }
            if self[index].item != nil, let removed = self[index].item!.remove(id: id) {
                return removed
            }
        }
        return nil
    }

    mutating func move(id: String, toParent parentID: String?, afterID: String? = nil, atStart: Bool = false) -> Bool {
        if id == parentID { return false }
        if isDescendant(parentID, of: id) { return false }
        guard let moving = firstItem(id: id) else { return false }

        let siblings: [CollectionItem]
        if let parentID {
            guard let parent = firstItem(id: parentID), parent.isFolder else { return false }
            siblings = parent.item ?? []
        } else {
            siblings = self
        }

        var destIndex = siblings.count
        if atStart {
            destIndex = 0
        } else if let afterID, let afterIndex = siblings.firstIndex(where: { $0.id == afterID }) {
            destIndex = afterIndex + 1
        }
        if let sourceIndex = siblings.firstIndex(where: { $0.id == id }), sourceIndex < destIndex {
            destIndex -= 1
        }

        guard remove(id: id) != nil else { return false }
        return insert(moving, parentID: parentID, at: destIndex)
    }

    private func clamped(_ index: Int?, count: Int) -> Int {
        Swift.min(Swift.max(index ?? count, 0), count)
    }
}
