import Foundation

enum CurlExporter {
    static func command(from urlRequest: URLRequest) -> String {
        var parts = ["curl"]
        let method = (urlRequest.httpMethod ?? "GET").uppercased()
        if method != "GET" {
            parts.append("-X")
            parts.append(quote(method))
        }

        let headers = (urlRequest.allHTTPHeaderFields ?? [:])
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        for (key, value) in headers {
            parts.append("-H")
            parts.append(quote("\(key): \(value)"))
        }

        if let body = urlRequest.httpBody, !body.isEmpty, let text = String(data: body, encoding: .utf8) {
            parts.append("--data-raw")
            parts.append(quote(text))
        }

        if let url = urlRequest.url?.absoluteString, !url.isEmpty {
            parts.append(quote(url))
        }
        return parts.joined(separator: " ")
    }

    static func command(from request: HTTPRequest) -> String {
        var parts = ["curl"]
        let method = request.method.uppercased()
        if method != "GET" {
            parts.append("-X")
            parts.append(quote(method))
        }
        for header in request.enabledHeaders {
            parts.append("-H")
            parts.append(quote("\(header.key): \(header.value)"))
        }
        if !["GET", "HEAD"].contains(method), let payload = request.body?.encodedPayload(),
           let text = String(data: payload.data, encoding: .utf8) {
            parts.append("--data-raw")
            parts.append(quote(text))
        }
        let url = request.rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.isEmpty {
            parts.append(quote(url))
        }
        return parts.joined(separator: " ")
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
