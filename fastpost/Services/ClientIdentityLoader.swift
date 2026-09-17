import CryptoKit
import Foundation
import Security

struct ClientTLSCredential: @unchecked Sendable {
    let identity: SecIdentity
    let certificates: [Any]
    private let retainedKeychain: RetainedKeychain?

    init(identity: SecIdentity, certificates: [Any], retainedKeychain: RetainedKeychain? = nil) {
        self.identity = identity
        self.certificates = certificates
        self.retainedKeychain = retainedKeychain
    }

    var urlCredential: URLCredential {
        URLCredential(
            identity: identity,
            certificates: certificates.isEmpty ? nil : certificates,
            persistence: .forSession
        )
    }
}

final class RetainedKeychain: @unchecked Sendable {
    let keychain: SecKeychain
    let url: URL

    init(keychain: SecKeychain, url: URL) {
        self.keychain = keychain
        self.url = url
    }

    deinit {
        SecKeychainDelete(keychain)
        try? FileManager.default.removeItem(at: url)
    }
}

enum ClientIdentityError: Error, Equatable {
    case missingMaterial
    case invalidCertificate
    case invalidPrivateKey
    case invalidPKCS12
    case incorrectPassphrase
    case identityUnavailable

    var transportMessage: String {
        switch self {
        case .missingMaterial:
            String(localized: "Add the certificate files before sending.")
        case .invalidCertificate:
            String(localized: "This file is not a valid certificate.")
        case .invalidPrivateKey:
            String(localized: "This file is not a valid private key.")
        case .invalidPKCS12:
            String(localized: "This file is not a valid PKCS#12 identity.")
        case .incorrectPassphrase:
            String(localized: "The certificate password is incorrect.")
        case .identityUnavailable:
            String(localized: "Fastpost could not build a TLS identity from these files.")
        }
    }
}

enum ClientIdentityLoader: Sendable {
    nonisolated static func load(material: ClientCertificateMaterial, passphrase: String) throws -> ClientTLSCredential {
        guard material.hasRequiredFiles else { throw ClientIdentityError.missingMaterial }
        switch material.kind {
        case .pfx:
            return try loadPKCS12(material.pkcs12Data ?? Data(), passphrase: passphrase)
        case .pem:
            return try loadPEM(
                certificateData: material.certificateData ?? Data(),
                privateKeyData: material.privateKeyData ?? Data(),
                passphrase: passphrase
            )
        }
    }

    nonisolated static func fingerprint(material: ClientCertificateMaterial, passphrase: String) -> String {
        var hasher = SHA256()
        hasher.update(data: material.certificateData ?? Data())
        hasher.update(data: material.privateKeyData ?? Data())
        hasher.update(data: material.pkcs12Data ?? Data())
        hasher.update(data: Data(passphrase.utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func loadPKCS12(_ data: Data, passphrase: String) throws -> ClientTLSCredential {
        let options: NSDictionary = [
            kSecImportExportPassphrase: passphrase,
            kSecImportToMemoryOnly: kCFBooleanTrue as Any
        ]
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options, &items)

        if status == errSecAuthFailed || status == errSecPkcs12VerifyFailure {
            throw ClientIdentityError.incorrectPassphrase
        }
        guard status == errSecSuccess, let imported = items as? [[String: Any]], let first = imported.first else {
            throw ClientIdentityError.invalidPKCS12
        }
        guard let identity = first[kSecImportItemIdentity as String] as! SecIdentity? else {
            throw ClientIdentityError.identityUnavailable
        }
        let chain = first[kSecImportItemCertChain as String] as? [Any] ?? []
        return ClientTLSCredential(
            identity: identity,
            certificates: chainExcludingLeaf(identity: identity, chain: chain)
        )
    }

    nonisolated private static func loadPEM(
        certificateData: Data,
        privateKeyData: Data,
        passphrase: String
    ) throws -> ClientTLSCredential {
        let certificates = try readCertificates(from: certificateData)
        guard let leaf = certificates.first else {
            throw ClientIdentityError.invalidCertificate
        }

        let retained = try makeTemporaryKeychain()
        do {
            try importItems(certificateData, fileName: "certificate.crt", passphrase: "", into: retained.keychain)
        } catch {
            throw ClientIdentityError.invalidCertificate
        }
        do {
            try importItems(privateKeyData, fileName: "private.key", passphrase: passphrase, into: retained.keychain)
        } catch ClientIdentityError.incorrectPassphrase {
            throw ClientIdentityError.incorrectPassphrase
        } catch {
            throw ClientIdentityError.invalidPrivateKey
        }

        var identity: SecIdentity?
        let status = SecIdentityCreateWithCertificate(retained.keychain, leaf, &identity)
        guard status == errSecSuccess, let identity else {
            throw ClientIdentityError.identityUnavailable
        }
        return ClientTLSCredential(
            identity: identity,
            certificates: chainExcludingLeaf(identity: identity, chain: certificates),
            retainedKeychain: retained
        )
    }

    nonisolated private static func chainExcludingLeaf(identity: SecIdentity, chain: [Any]) -> [Any] {
        var leaf: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &leaf) == errSecSuccess, let leaf else {
            return chain
        }
        let leafData = SecCertificateCopyData(leaf) as Data
        return chain.filter { item in
            let object = item as AnyObject
            guard CFGetTypeID(object) == SecCertificateGetTypeID() else { return true }
            return SecCertificateCopyData(item as! SecCertificate) as Data != leafData
        }
    }

    nonisolated private static func readCertificates(from data: Data) throws -> [SecCertificate] {
        let parsed = PEMParser.parse(data)
        let ders = parsed.certificates.isEmpty ? [data] : parsed.certificates
        let certificates = ders.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        guard !certificates.isEmpty else { throw ClientIdentityError.invalidCertificate }
        return certificates
    }

    nonisolated private static func importItems(
        _ data: Data,
        fileName: String,
        passphrase: String,
        into keychain: SecKeychain
    ) throws {
        var format = SecExternalFormat.formatUnknown
        var itemType = SecExternalItemType.itemTypeUnknown
        var items: CFArray?
        var params = SecItemImportExportKeyParameters()
        params.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
        params.flags = SecKeyImportExportFlags()
        let cfPassphrase = passphrase as CFString
        params.passphrase = passphrase.isEmpty ? nil : Unmanaged.passUnretained(cfPassphrase)

        let status = SecItemImport(
            data as CFData,
            fileName as CFString,
            &format,
            &itemType,
            [],
            &params,
            keychain,
            &items
        )
        if status == errSecPassphraseRequired || status == errSecAuthFailed || status == errSecPkcs12VerifyFailure {
            throw ClientIdentityError.incorrectPassphrase
        }
        guard status == errSecSuccess else {
            throw ClientIdentityError.identityUnavailable
        }
    }

    nonisolated private static func makeTemporaryKeychain() throws -> RetainedKeychain {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "fastpost-\(UUID().uuidString).keychain-db")
        var keychain: SecKeychain?
        let password = "fastpost-temp"
        let status = url.path.withCString { path in
            password.withCString { pwd in
                SecKeychainCreate(path, UInt32(password.utf8.count), pwd, false, nil, &keychain)
            }
        }
        guard status == errSecSuccess, let keychain else {
            throw ClientIdentityError.identityUnavailable
        }
        SecKeychainSetUserInteractionAllowed(false)
        password.withCString { pwd in
            _ = SecKeychainUnlock(keychain, UInt32(password.utf8.count), pwd, true)
        }
        return RetainedKeychain(keychain: keychain, url: url)
    }
}

actor ClientIdentityCache {
    private struct CacheKey: Hashable {
        var id: UUID
        var fingerprint: String
    }

    private var cache: [CacheKey: ClientTLSCredential] = [:]

    func credential(for certificate: ClientCertificate, material: ClientCertificateMaterial) throws -> ClientTLSCredential {
        let fingerprint = ClientIdentityLoader.fingerprint(material: material, passphrase: certificate.passphrase)
        let key = CacheKey(id: certificate.id, fingerprint: fingerprint)
        if let cached = cache[key] {
            return cached
        }
        cache = cache.filter { $0.key.id != certificate.id }
        let loaded = try ClientIdentityLoader.load(material: material, passphrase: certificate.passphrase)
        cache[key] = loaded
        return loaded
    }
}

enum PEMParser: Sendable {
    struct Parsed: Equatable, Sendable {
        var certificates: [Data]
        var keys: [Data]
        var encryptedKeys: [Data]
        var rawKeyPEMs: [Data]

        nonisolated init(
            certificates: [Data] = [],
            keys: [Data] = [],
            encryptedKeys: [Data] = [],
            rawKeyPEMs: [Data] = []
        ) {
            self.certificates = certificates
            self.keys = keys
            self.encryptedKeys = encryptedKeys
            self.rawKeyPEMs = rawKeyPEMs
        }
    }

    nonisolated static func looksLikePEM(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains("-----BEGIN ")
    }

    nonisolated static func parse(_ data: Data) -> Parsed {
        guard let text = String(data: data, encoding: .utf8) else { return Parsed() }
        let pattern = #"-----BEGIN ([A-Z0-9 ]+)-----\r?\n([A-Za-z0-9+/=\r\n]+)-----END \1-----"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return Parsed() }

        var parsed = Parsed()
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        for match in regex.matches(in: text, range: range) {
            let type = nsText.substring(with: match.range(at: 1))
            let body = nsText.substring(with: match.range(at: 2)).filter { !$0.isWhitespace }
            let pemBlock = Data(nsText.substring(with: match.range).utf8)
            guard let der = Data(base64Encoded: body) else { continue }

            switch type {
            case "CERTIFICATE":
                parsed.certificates.append(der)
            case "PRIVATE KEY", "RSA PRIVATE KEY", "EC PRIVATE KEY":
                parsed.keys.append(der)
                parsed.rawKeyPEMs.append(pemBlock)
            case "ENCRYPTED PRIVATE KEY":
                parsed.encryptedKeys.append(der)
                parsed.rawKeyPEMs.append(pemBlock)
            default:
                break
            }
        }
        return parsed
    }

}
