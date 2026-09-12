import Foundation

enum ClientCertificateMatcher: Sendable {
    struct Target: Equatable, Hashable {
        var host: String
        var port: Int
    }

    static func target(from rawURL: String) -> Target? {
        var raw = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") {
            raw = "https://\(raw)"
        }
        guard let components = URLComponents(string: raw),
              let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty
        else {
            return nil
        }

        let scheme = components.scheme?.lowercased() ?? "https"
        let port = components.port ?? (scheme == "http" ? 80 : 443)
        return Target(host: normalizedHost(host), port: port)
    }

    static func match(_ certificates: [ClientCertificate], host: String, port: Int) -> ClientCertificate? {
        let needle = normalizedHost(host)
        guard !needle.isEmpty else { return nil }

        let matches = certificates.filter { certificate in
            guard certificate.isEnabled else { return false }
            guard normalizedHost(certificate.host) == needle else { return false }
            if let certificatePort = certificate.port {
                return certificatePort == port
            }
            return true
        }

        return matches.first { $0.port == port } ?? matches.first
    }

    static func match(_ certificates: [ClientCertificate], rawURL: String) -> ClientCertificate? {
        guard let target = target(from: rawURL) else { return nil }
        return match(certificates, host: target.host, port: target.port)
    }

    private static func normalizedHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }
}
