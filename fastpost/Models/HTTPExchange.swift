import Foundation

enum RequestRunState: Equatable {
    case idle
    case sending
    case received(HTTPExchange)
    case failed(HTTPTransportFailure)
}

struct HTTPSendOutcome: Sendable {
    var exchange: HTTPExchange
    var rawBody: Data
}

struct HTTPExchange: Equatable, Sendable {
    var statusCode: Int
    var statusText: String
    var duration: Duration
    var byteCount: Int
    var headers: [HTTPHeader]
    var cookies: [ResponseCookie]
    var body: ResponseBody
    var requestURL: URL
    var finalURL: URL
    var isTruncated: Bool

    var statusFamily: StatusFamily {
        switch statusCode {
        case 100..<200: .informational
        case 200..<300: .success
        case 300..<400: .redirect
        case 400..<500: .clientError
        case 500..<600: .serverError
        default: .unknown
        }
    }

    var durationMilliseconds: Int {
        Int(duration / .milliseconds(1))
    }

    var showsFinalURL: Bool {
        requestURL.absoluteString != finalURL.absoluteString
    }

    var statusDisplay: String {
        statusText.isEmpty ? "\(statusCode)" : "\(statusCode) \(statusText)"
    }
}

enum StatusFamily: Equatable {
    case informational, success, redirect, clientError, serverError, unknown
}

enum ResponseBody: Equatable, Sendable {
    case empty
    case json(String)
    case text(String)
    case binary(mime: String)

    var copyableText: String? {
        switch self {
        case .empty, .binary: nil
        case .json(let text), .text(let text): text
        }
    }
}

struct ResponseCookie: Identifiable, Equatable, Hashable, Sendable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var isSecure: Bool
    var isHTTPOnly: Bool

    var id: String { "\(domain)|\(path)|\(name)" }
}

enum HTTPTransportFailure: Error, Equatable {
    case invalidURL
    case timeout
    case cancelled
    case offline
    case dns
    case tls
    case clientCertificate(String)
    case unreachable
    case unknown(String)

    var title: LocalizedStringResource {
        switch self {
        case .invalidURL: "Invalid URL"
        case .timeout: "Request Timed Out"
        case .cancelled: "Request Cancelled"
        case .offline: "You Are Offline"
        case .dns: "Host Not Found"
        case .tls: "Secure Connection Failed"
        case .clientCertificate: "Client Certificate Failed"
        case .unreachable: "Could Not Connect"
        case .unknown: "Request Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .invalidURL: "link.badge.plus"
        case .timeout: "clock.badge.exclamationmark"
        case .cancelled: "stop.circle"
        case .offline: "wifi.slash"
        case .dns: "globe.badge.chevron.backward"
        case .tls: "lock.slash"
        case .clientCertificate: "lock.doc"
        case .unreachable: "network.slash"
        case .unknown: "exclamationmark.triangle"
        }
    }

    var message: String {
        switch self {
        case .invalidURL:
            String(localized: "Check the URL and try again.")
        case .timeout:
            String(localized: "The server took too long to respond.")
        case .cancelled:
            String(localized: "The request was stopped before it finished.")
        case .offline:
            String(localized: "Connect to the internet and try again.")
        case .dns:
            String(localized: "The host name could not be resolved.")
        case .tls:
            String(localized: "The TLS handshake or certificate check failed.")
        case .clientCertificate(let detail):
            detail
        case .unreachable:
            String(localized: "The host refused the connection or dropped it.")
        case .unknown(let detail):
            detail
        }
    }
}

enum HTTPClientError: Error {
    case invalidURL
}
