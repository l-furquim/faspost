import Foundation
import Network

struct HTTPClient: Sendable {
    var preferences: RequestPreferences = .default
    var clientCredential: ClientTLSCredential?
    nonisolated(unsafe) var cookieStorage: HTTPCookieStorage?

    var timeout: TimeInterval { preferences.timeoutInterval }
    var previewLimit: Int { preferences.previewLimit }

    func send(_ request: HTTPRequest) async -> Result<HTTPExchange, HTTPTransportFailure> {
        do {
            let urlRequest = try makeURLRequest(from: request)
            let session = makeSession(originalRequest: urlRequest)
            defer { session.finishTasksAndInvalidate() }
            let clock = ContinuousClock()
            let started = clock.now
            let (data, response) = try await session.data(for: urlRequest)
            let duration = clock.now - started
            guard let http = response as? HTTPURLResponse else {
                return .failure(.unknown(String(localized: "The server returned an unexpected response.")))
            }
            return .success(makeExchange(data: data, response: http, requestURL: urlRequest.url ?? http.url!, duration: duration))
        } catch is HTTPClientError {
            return .failure(.invalidURL)
        } catch {
            if Task.isCancelled {
                return .failure(.cancelled)
            }
            return .failure(Self.map(error))
        }
    }

    func makeURLRequest(from request: HTTPRequest) throws -> URLRequest {
        guard let url = makeURL(from: request) else {
            throw HTTPClientError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = timeout

        for header in request.enabledHeaders {
            urlRequest.setValue(header.value, forHTTPHeaderField: header.key)
        }

        applyAuth(request.auth, to: &urlRequest)
        urlRequest.assumesHTTP3Capable = preferences.httpVersion == .http3

        if preferences.sendNoCache, urlRequest.value(forHTTPHeaderField: "Cache-Control") == nil {
            urlRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }

        if Self.methodAllowsBody(request.method), let payload = request.body?.encodedPayload() {
            urlRequest.httpBody = payload.data
            if urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
                urlRequest.setValue(payload.contentType, forHTTPHeaderField: "Content-Type")
            }
        }

        return urlRequest
    }

    private func makeURL(from request: HTTPRequest) -> URL? {
        var raw = request.rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") {
            raw = "https://\(raw)"
        }
        if preferences.encodeURL {
            return encodedURL(raw, request: request)
        }
        return rawURL(raw, request: request)
    }

    private func encodedURL(_ raw: String, request: HTTPRequest) -> URL? {
        guard var components = URLComponents(string: raw) else { return nil }
        var items = components.queryItems ?? []
        if request.auth?.kind == .apiKey, request.auth?.apiKeyLocation == .query {
            let name = request.auth?.apiKeyName ?? ""
            let value = request.auth?.apiKeyValue ?? ""
            if !name.isEmpty {
                items.removeAll { $0.name == name }
                items.append(URLQueryItem(name: name, value: value))
            }
        }
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }

    private func rawURL(_ raw: String, request: HTTPRequest) -> URL? {
        var candidate = raw
        if request.auth?.kind == .apiKey, request.auth?.apiKeyLocation == .query {
            let name = request.auth?.apiKeyName ?? ""
            let value = request.auth?.apiKeyValue ?? ""
            if !name.isEmpty {
                let separator = candidate.contains("?") ? "&" : "?"
                candidate += "\(separator)\(name)=\(value)"
            }
        }
        return URL(string: candidate)
    }

    private func applyAuth(_ auth: RequestAuth?, to request: inout URLRequest) {
        guard let auth else { return }
        switch auth.kind {
        case .none:
            break
        case .basic:
            let raw = "\(auth.username):\(auth.password)"
            let encoded = Data(raw.utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        case .bearer:
            let token = auth.token
            guard !token.isEmpty else { return }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .apiKey:
            guard auth.apiKeyLocation == .header, !auth.apiKeyName.isEmpty else { return }
            request.setValue(auth.apiKeyValue, forHTTPHeaderField: auth.apiKeyName)
        }
    }

    private func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        if preferences.useCookieJar, let cookieStorage {
            configuration.httpCookieStorage = cookieStorage
            configuration.httpShouldSetCookies = true
            configuration.httpCookieAcceptPolicy = .always
        } else {
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
        }
        switch preferences.tlsMinimum {
        case .system:
            break
        case .tls12:
            configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        case .tls13:
            configuration.tlsMinimumSupportedProtocolVersion = .TLSv13
        }
        return configuration
    }

    private func makeSession(originalRequest: URLRequest) -> URLSession {
        let delegate = HTTPSessionDelegate(
            preferences: preferences,
            clientCredential: clientCredential,
            originalRequest: originalRequest
        )
        return URLSession(configuration: makeSessionConfiguration(), delegate: delegate, delegateQueue: nil)
    }

    private func makeExchange(
        data: Data,
        response: HTTPURLResponse,
        requestURL: URL,
        duration: Duration
    ) -> HTTPExchange {
        let headers = response.allHeaderFields
            .compactMap { key, value -> HTTPHeader? in
                HTTPHeader(key: "\(key)", value: "\(value)")
            }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }

        let cookieFields = Dictionary(uniqueKeysWithValues: headers.map { ($0.key, $0.value) })
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: cookieFields, for: response.url ?? requestURL)
            .map { cookie in
                ResponseCookie(
                    name: cookie.name,
                    value: cookie.value,
                    domain: cookie.domain,
                    path: cookie.path,
                    isSecure: cookie.isSecure,
                    isHTTPOnly: cookie.isHTTPOnly
                )
            }

        let isTruncated = data.count > previewLimit
        let preview = isTruncated ? Data(data.prefix(previewLimit)) : data
        let mime = response.mimeType ?? headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value ?? ""

        return HTTPExchange(
            statusCode: response.statusCode,
            statusText: HTTPStatusPhrase.phrase(for: response.statusCode),
            duration: duration,
            byteCount: data.count,
            headers: headers,
            cookies: cookies,
            body: decodeBody(preview, mime: mime),
            requestURL: requestURL,
            finalURL: response.url ?? requestURL,
            isTruncated: isTruncated
        )
    }

    private func decodeBody(_ data: Data, mime: String) -> ResponseBody {
        if data.isEmpty { return .empty }

        let looksJSON = mime.localizedCaseInsensitiveContains("json")
            || (data.first == UInt8(ascii: "{") || data.first == UInt8(ascii: "["))

        if looksJSON,
           let object = try? JSONSerialization.jsonObject(with: data),
           JSONSerialization.isValidJSONObject(object) || object is [Any] || object is [String: Any],
           let pretty = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
           ),
           let text = String(data: pretty, encoding: .utf8)
        {
            return .json(text)
        }

        if let text = String(data: data, encoding: .utf8), text.unicodeScalars.allSatisfy({ $0.isASCII || !$0.properties.isNoncharacterCodePoint }) {
            if text.contains("\u{0}") {
                return .binary(mime: mime.isEmpty ? "application/octet-stream" : mime)
            }
            return .text(text)
        }

        return .binary(mime: mime.isEmpty ? "application/octet-stream" : mime)
    }

    private static func methodAllowsBody(_ method: String) -> Bool {
        !["GET", "HEAD"].contains(method.uppercased())
    }

    static func map(_ error: Error) -> HTTPTransportFailure {
        guard let urlError = error as? URLError else {
            return .unknown(error.localizedDescription)
        }
        switch urlError.code {
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        case .cannotFindHost, .dnsLookupFailed:
            return .dns
        case .clientCertificateRejected:
            return .clientCertificate(String(localized: "The server rejected the client certificate."))
        case .clientCertificateRequired:
            return .clientCertificate(String(localized: "The server requested a client certificate, but none matched this host."))
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot,
                .appTransportSecurityRequiresSecureConnection:
            return .tls
        case .cannotConnectToHost, .networkConnectionLost:
            return .unreachable
        default:
            return .unknown(urlError.localizedDescription)
        }
    }
}

private final class HTTPSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    let preferences: RequestPreferences
    let clientCredential: ClientTLSCredential?
    let originalRequest: URLRequest
    private var redirectCount = 0

    init(
        preferences: RequestPreferences,
        clientCredential: ClientTLSCredential?,
        originalRequest: URLRequest
    ) {
        self.preferences = preferences
        self.clientCredential = clientCredential
        self.originalRequest = originalRequest
    }

    nonisolated func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge, completionHandler: completionHandler)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge, completionHandler: completionHandler)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(redirectedRequest(from: request))
    }

    private nonisolated func redirectedRequest(from request: URLRequest) -> URLRequest? {
        guard preferences.followRedirects else { return nil }
        if preferences.maxRedirects > 0, redirectCount >= preferences.maxRedirects {
            return nil
        }
        redirectCount += 1

        var next = request
        if preferences.preserveMethodOnRedirect {
            next.httpMethod = originalRequest.httpMethod
            next.httpBody = originalRequest.httpBody
            if let contentType = originalRequest.value(forHTTPHeaderField: "Content-Type") {
                next.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }

        let originalHost = originalRequest.url?.host
        let nextHost = next.url?.host
        let hostChanged = Self.host(originalHost) != Self.host(nextHost)
        if hostChanged {
            if preferences.followAuthorizationHeader {
                if next.value(forHTTPHeaderField: "Authorization") == nil,
                   let authorization = originalRequest.value(forHTTPHeaderField: "Authorization") {
                    next.setValue(authorization, forHTTPHeaderField: "Authorization")
                }
            } else {
                next.setValue(nil, forHTTPHeaderField: "Authorization")
            }
        }

        if preferences.removeRefererOnRedirect {
            next.setValue(nil, forHTTPHeaderField: "Referer")
        }
        return next
    }

    private nonisolated static func host(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private nonisolated func handle(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod
        if method == NSURLAuthenticationMethodClientCertificate {
            if let clientCredential {
                completionHandler(.useCredential, clientCredential.urlCredential)
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
            return
        }

        guard !preferences.verifySSL,
              method == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
