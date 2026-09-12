import Foundation

struct RequestAuth: Codable, Equatable, Hashable {
    var type: String
    var basic: [AuthAttribute]?
    var bearer: [AuthAttribute]?
    var apikey: [AuthAttribute]?

    static let none = RequestAuth(type: "noauth")

    static func basic(username: String, password: String) -> RequestAuth {
        RequestAuth(
            type: "basic",
            basic: [
                AuthAttribute(key: "username", value: username),
                AuthAttribute(key: "password", value: password),
            ]
        )
    }

    static func bearer(token: String) -> RequestAuth {
        RequestAuth(type: "bearer", bearer: [AuthAttribute(key: "token", value: token)])
    }

    static func apiKey(key: String, value: String, location: APIKeyLocation) -> RequestAuth {
        RequestAuth(
            type: "apikey",
            apikey: [
                AuthAttribute(key: "key", value: key),
                AuthAttribute(key: "value", value: value),
                AuthAttribute(key: "in", value: location.rawValue),
            ]
        )
    }

    var kind: AuthKind {
        get { AuthKind(rawValue: type) ?? .none }
        set {
            type = newValue.rawValue
            switch newValue {
            case .none:
                basic = nil
                bearer = nil
                apikey = nil
            case .basic:
                if basic == nil { basic = [AuthAttribute(key: "username", value: ""), AuthAttribute(key: "password", value: "")] }
            case .bearer:
                if bearer == nil { bearer = [AuthAttribute(key: "token", value: "")] }
            case .apiKey:
                if apikey == nil {
                    apikey = [
                        AuthAttribute(key: "key", value: ""),
                        AuthAttribute(key: "value", value: ""),
                        AuthAttribute(key: "in", value: APIKeyLocation.header.rawValue),
                    ]
                }
            }
        }
    }

    var isNone: Bool { kind == .none }

    var username: String {
        get { attribute(basic, key: "username") }
        set { setAttribute(&basic, key: "username", value: newValue) }
    }

    var password: String {
        get { attribute(basic, key: "password") }
        set { setAttribute(&basic, key: "password", value: newValue) }
    }

    var token: String {
        get { attribute(bearer, key: "token") }
        set { setAttribute(&bearer, key: "token", value: newValue) }
    }

    var apiKeyName: String {
        get { attribute(apikey, key: "key") }
        set { setAttribute(&apikey, key: "key", value: newValue) }
    }

    var apiKeyValue: String {
        get { attribute(apikey, key: "value") }
        set { setAttribute(&apikey, key: "value", value: newValue) }
    }

    var apiKeyLocation: APIKeyLocation {
        get { APIKeyLocation(rawValue: attribute(apikey, key: "in")) ?? .header }
        set { setAttribute(&apikey, key: "in", value: newValue.rawValue) }
    }

    private func attribute(_ list: [AuthAttribute]?, key: String) -> String {
        list?.first(where: { $0.key == key })?.value ?? ""
    }

    private func setAttribute(_ list: inout [AuthAttribute]?, key: String, value: String) {
        var items = list ?? []
        if let index = items.firstIndex(where: { $0.key == key }) {
            items[index].value = value
        } else {
            items.append(AuthAttribute(key: key, value: value))
        }
        list = items
    }
}

struct AuthAttribute: Codable, Equatable, Hashable {
    var key: String
    var value: String
    var type: String? = "string"
}

enum AuthKind: String, CaseIterable, Identifiable {
    case none = "noauth"
    case basic
    case bearer
    case apiKey = "apikey"

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .none: "No Auth"
        case .basic: "Basic"
        case .bearer: "Bearer"
        case .apiKey: "API Key"
        }
    }
}

enum APIKeyLocation: String, CaseIterable, Identifiable {
    case header
    case query

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .header: "Header"
        case .query: "Query"
        }
    }
}
