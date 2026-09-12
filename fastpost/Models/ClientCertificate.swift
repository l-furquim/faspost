import Foundation

enum ClientCertificateKind: String, Codable, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
    case pem
    case pfx

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .pem: "PEM (CRT + KEY)"
        case .pfx: "PKCS#12 (PFX)"
        }
    }
}

struct ClientCertificate: Identifiable, Equatable, Hashable, Codable {
    var id: UUID
    var host: String
    var port: Int?
    var kind: ClientCertificateKind
    var isEnabled: Bool
    var passphrase: String
    var crtFileName: String?
    var keyFileName: String?
    var pfxFileName: String?
    var crtDisplayName: String?
    var keyDisplayName: String?
    var pfxDisplayName: String?

    init(
        id: UUID = UUID(),
        host: String = "",
        port: Int? = nil,
        kind: ClientCertificateKind = .pem,
        isEnabled: Bool = true,
        passphrase: String = "",
        crtFileName: String? = nil,
        keyFileName: String? = nil,
        pfxFileName: String? = nil,
        crtDisplayName: String? = nil,
        keyDisplayName: String? = nil,
        pfxDisplayName: String? = nil
    ) {
        self.id = id
        self.host = host
        self.port = port
        self.kind = kind
        self.isEnabled = isEnabled
        self.passphrase = passphrase
        self.crtFileName = crtFileName
        self.keyFileName = keyFileName
        self.pfxFileName = pfxFileName
        self.crtDisplayName = crtDisplayName
        self.keyDisplayName = keyDisplayName
        self.pfxDisplayName = pfxDisplayName
    }

    var listTitle: String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "New Certificate") : trimmed
    }

    var listSubtitle: String {
        var parts: [String] = [
            kind == .pem ? String(localized: "PEM") : String(localized: "PFX")
        ]
        if let port {
            parts.append(String(port))
        }
        if !isEnabled {
            parts.append(String(localized: "Off"))
        }
        return parts.joined(separator: " · ")
    }

    var hasCertificateFile: Bool { crtDisplayName != nil && crtFileName != nil }
    var hasKeyFile: Bool { keyDisplayName != nil && keyFileName != nil }
    var hasPKCS12File: Bool { pfxDisplayName != nil && pfxFileName != nil }

    var hasRequiredFiles: Bool {
        switch kind {
        case .pem: hasCertificateFile && hasKeyFile
        case .pfx: hasPKCS12File
        }
    }
}

struct ClientCertificateMaterial: Sendable, Equatable {
    var kind: ClientCertificateKind
    var certificateData: Data?
    var privateKeyData: Data?
    var pkcs12Data: Data?

    nonisolated var hasRequiredFiles: Bool {
        switch kind {
        case .pem: certificateData != nil && privateKeyData != nil
        case .pfx: pkcs12Data != nil
        }
    }
}

enum CertificateFileRole: Equatable, Hashable {
    case certificate
    case privateKey
    case pkcs12
}

struct ClientCertificateIndex: Codable, Equatable {
    var certificates: [ClientCertificate]
}
