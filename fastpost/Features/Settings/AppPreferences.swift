import AppKit
import Foundation

enum AppPreferenceStorage {
    static let timeoutSeconds = "request.timeoutSeconds"
    static let maxResponseMB = "request.maxResponseMB"
    static let verifySSL = "request.verifySSL"
    static let followRedirects = "request.followRedirects"
    static let sendNoCache = "request.sendNoCache"
    static let httpVersion = "request.httpVersion"
    static let encodeURL = "request.encodeURL"
    static let useCookieJar = "request.useCookieJar"
    static let maxRedirects = "request.maxRedirects"
    static let preserveMethodOnRedirect = "request.preserveMethodOnRedirect"
    static let followAuthorizationHeader = "request.followAuthorizationHeader"
    static let removeRefererOnRedirect = "request.removeRefererOnRedirect"
    static let tlsMinimum = "request.tlsMinimum"
    static let editorFontSize = "editor.fontSize"
    static let editorIndentSpaces = "editor.indentSpaces"
}

enum HTTPVersionPreference: String, CaseIterable, Identifiable, Equatable, Sendable {
    case automatic
    case http3

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .automatic: "Automatic"
        case .http3: "HTTP/3"
        }
    }
}

enum TLSMinimumVersion: String, CaseIterable, Identifiable, Equatable, Sendable {
    case system
    case tls12
    case tls13

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .tls12: "TLS 1.2"
        case .tls13: "TLS 1.3"
        }
    }
}

struct RequestPreferences: Equatable, Sendable {
    var timeoutSeconds: Double
    var maxResponseMB: Double
    var verifySSL: Bool
    var followRedirects: Bool
    var sendNoCache: Bool
    var httpVersion: HTTPVersionPreference
    var encodeURL: Bool
    var useCookieJar: Bool
    var maxRedirects: Int
    var preserveMethodOnRedirect: Bool
    var followAuthorizationHeader: Bool
    var removeRefererOnRedirect: Bool
    var tlsMinimum: TLSMinimumVersion

    static let `default` = RequestPreferences(
        timeoutSeconds: 30,
        maxResponseMB: 1,
        verifySSL: true,
        followRedirects: true,
        sendNoCache: true,
        httpVersion: .automatic,
        encodeURL: true,
        useCookieJar: false,
        maxRedirects: 10,
        preserveMethodOnRedirect: false,
        followAuthorizationHeader: false,
        removeRefererOnRedirect: false,
        tlsMinimum: .system
    )

    static var current: RequestPreferences {
        let defaults = UserDefaults.standard
        return RequestPreferences(
            timeoutSeconds: defaults.double(ifPresent: AppPreferenceStorage.timeoutSeconds) ?? Self.default.timeoutSeconds,
            maxResponseMB: defaults.double(ifPresent: AppPreferenceStorage.maxResponseMB) ?? Self.default.maxResponseMB,
            verifySSL: defaults.bool(ifPresent: AppPreferenceStorage.verifySSL) ?? Self.default.verifySSL,
            followRedirects: defaults.bool(ifPresent: AppPreferenceStorage.followRedirects) ?? Self.default.followRedirects,
            sendNoCache: defaults.bool(ifPresent: AppPreferenceStorage.sendNoCache) ?? Self.default.sendNoCache,
            httpVersion: HTTPVersionPreference(rawValue: defaults.string(ifPresent: AppPreferenceStorage.httpVersion) ?? "") ?? Self.default.httpVersion,
            encodeURL: defaults.bool(ifPresent: AppPreferenceStorage.encodeURL) ?? Self.default.encodeURL,
            useCookieJar: defaults.bool(ifPresent: AppPreferenceStorage.useCookieJar) ?? Self.default.useCookieJar,
            maxRedirects: defaults.integer(ifPresent: AppPreferenceStorage.maxRedirects) ?? Self.default.maxRedirects,
            preserveMethodOnRedirect: defaults.bool(ifPresent: AppPreferenceStorage.preserveMethodOnRedirect) ?? Self.default.preserveMethodOnRedirect,
            followAuthorizationHeader: defaults.bool(ifPresent: AppPreferenceStorage.followAuthorizationHeader) ?? Self.default.followAuthorizationHeader,
            removeRefererOnRedirect: defaults.bool(ifPresent: AppPreferenceStorage.removeRefererOnRedirect) ?? Self.default.removeRefererOnRedirect,
            tlsMinimum: TLSMinimumVersion(rawValue: defaults.string(ifPresent: AppPreferenceStorage.tlsMinimum) ?? "") ?? Self.default.tlsMinimum
        )
    }

    var timeoutInterval: TimeInterval {
        timeoutSeconds <= 0 ? 60 * 60 * 24 * 7 : timeoutSeconds
    }

    var previewLimit: Int {
        guard maxResponseMB > 0 else { return Int.max }
        let bytes = maxResponseMB * 1_048_576
        return Int(min(bytes, Double(Int.max)))
    }
}

struct EditorPreferences: Equatable, Sendable {
    var fontSize: Double
    var indentSpaces: Int

    static let `default` = EditorPreferences(
        fontSize: Double(NSFont.systemFontSize),
        indentSpaces: 4
    )

    static let indentOptions = [2, 4, 8]

    static var current: EditorPreferences {
        let defaults = UserDefaults.standard
        let size = defaults.double(ifPresent: AppPreferenceStorage.editorFontSize) ?? Self.default.fontSize
        let indent = defaults.integer(ifPresent: AppPreferenceStorage.editorIndentSpaces) ?? Self.default.indentSpaces
        return EditorPreferences(
            fontSize: min(max(size, 10), 22),
            indentSpaces: Self.indentOptions.contains(indent) ? indent : Self.default.indentSpaces
        )
    }

    var indentString: String {
        String(repeating: " ", count: indentSpaces)
    }
}

private extension UserDefaults {
    func double(ifPresent key: String) -> Double? {
        object(forKey: key) == nil ? nil : double(forKey: key)
    }

    func integer(ifPresent key: String) -> Int? {
        object(forKey: key) == nil ? nil : integer(forKey: key)
    }

    func bool(ifPresent key: String) -> Bool? {
        object(forKey: key) == nil ? nil : bool(forKey: key)
    }

    func string(ifPresent key: String) -> String? {
        object(forKey: key) == nil ? nil : string(forKey: key)
    }
}
