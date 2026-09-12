import Foundation

@Observable
final class ClientCertificateStore {
    var certificates: [ClientCertificate] = []

    @ObservationIgnored
    private let fileManager: FileManager
    @ObservationIgnored
    private let rootURL: URL?
    @ObservationIgnored
    private var persistTask: Task<Void, Never>?

    init(rootURL: URL? = nil, loadsFromDisk: Bool = true) {
        self.fileManager = .default
        self.rootURL = rootURL ?? Self.defaultRootURL()
        if loadsFromDisk {
            load()
        }
    }

    func match(host: String, port: Int) -> ClientCertificate? {
        ClientCertificateMatcher.match(certificates, host: host, port: port)
    }

    func match(rawURL: String) -> ClientCertificate? {
        ClientCertificateMatcher.match(certificates, rawURL: rawURL)
    }

    @discardableResult
    func create() -> ClientCertificate {
        let certificate = ClientCertificate()
        certificates.append(certificate)
        persistNow()
        return certificate
    }

    func delete(id: UUID) {
        certificates.removeAll { $0.id == id }
        persistNow()
        removeDirectory(for: id)
    }

    func setHost(_ host: String, id: UUID) {
        update(id, persist: .debounced) { $0.host = host }
    }

    func setPort(_ port: Int?, id: UUID) {
        update(id, persist: .debounced) { $0.port = port }
    }

    func setKind(_ kind: ClientCertificateKind, id: UUID) {
        update(id, persist: .immediate) { $0.kind = kind }
    }

    func setPassphrase(_ passphrase: String, id: UUID) {
        update(id, persist: .debounced) { $0.passphrase = passphrase }
    }

    func setEnabled(_ isEnabled: Bool, id: UUID) {
        update(id, persist: .immediate) { $0.isEnabled = isEnabled }
    }

    func importFile(_ data: Data, displayName: String, role: CertificateFileRole, id: UUID) {
        let parsed = PEMParser.parse(data)
        switch role {
        case .certificate:
            write(data, fileName: Self.crtFileName, id: id) { certificate in
                certificate.crtFileName = Self.crtFileName
                certificate.crtDisplayName = displayName
            }
            if !hasKeyFile(id: id), let keyPEM = parsed.rawKeyPEMs.first {
                write(keyPEM, fileName: Self.keyFileName, id: id) { certificate in
                    certificate.keyFileName = Self.keyFileName
                    certificate.keyDisplayName = displayName
                }
            }
        case .privateKey:
            let keyData = parsed.rawKeyPEMs.first ?? data
            write(keyData, fileName: Self.keyFileName, id: id) { certificate in
                certificate.keyFileName = Self.keyFileName
                certificate.keyDisplayName = displayName
            }
            if !hasCertificateFile(id: id), let der = parsed.certificates.first,
               let pem = pemCertificate(from: der) {
                write(pem, fileName: Self.crtFileName, id: id) { certificate in
                    certificate.crtFileName = Self.crtFileName
                    certificate.crtDisplayName = displayName
                }
            }
        case .pkcs12:
            write(data, fileName: Self.pfxFileName, id: id) { certificate in
                certificate.pfxFileName = Self.pfxFileName
                certificate.pfxDisplayName = displayName
            }
        }
    }

    func clearFile(_ role: CertificateFileRole, id: UUID) {
        guard let index = certificates.firstIndex(where: { $0.id == id }) else { return }
        let fileName: String?
        switch role {
        case .certificate:
            fileName = certificates[index].crtFileName
            certificates[index].crtFileName = nil
            certificates[index].crtDisplayName = nil
        case .privateKey:
            fileName = certificates[index].keyFileName
            certificates[index].keyFileName = nil
            certificates[index].keyDisplayName = nil
        case .pkcs12:
            fileName = certificates[index].pfxFileName
            certificates[index].pfxFileName = nil
            certificates[index].pfxDisplayName = nil
        }
        if let fileName {
            try? fileManager.removeItem(at: itemDirectory(for: id).appending(path: fileName))
        }
        persistNow()
    }

    func material(for certificate: ClientCertificate) throws -> ClientCertificateMaterial {
        switch certificate.kind {
        case .pem:
            return ClientCertificateMaterial(
                kind: .pem,
                certificateData: try readFile(certificate.crtFileName, id: certificate.id),
                privateKeyData: try readFile(certificate.keyFileName, id: certificate.id),
                pkcs12Data: nil
            )
        case .pfx:
            return ClientCertificateMaterial(
                kind: .pfx,
                certificateData: nil,
                privateKeyData: nil,
                pkcs12Data: try readFile(certificate.pfxFileName, id: certificate.id)
            )
        }
    }

    private func hasCertificateFile(id: UUID) -> Bool {
        certificates.first { $0.id == id }?.hasCertificateFile == true
    }

    private func hasKeyFile(id: UUID) -> Bool {
        certificates.first { $0.id == id }?.hasKeyFile == true
    }

    private func update(
        _ id: UUID,
        persist style: PersistenceStyle,
        mutate: (inout ClientCertificate) -> Void
    ) {
        guard let index = certificates.firstIndex(where: { $0.id == id }) else { return }
        var certificate = certificates[index]
        mutate(&certificate)
        guard certificate != certificates[index] else { return }
        certificates[index] = certificate
        persist(style)
    }

    private func persist(_ style: PersistenceStyle) {
        switch style {
        case .immediate:
            persistNow()
        case .debounced:
            schedulePersist()
        }
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            persistNow()
        }
    }

    private func persistNow() {
        persistTask?.cancel()
        persistTask = nil
        guard let rootURL else { return }
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(ClientCertificateIndex(certificates: certificates))
            try data.write(to: rootURL.appending(path: "index.json"), options: .atomic)
        } catch {
            return
        }
    }

    private func load() {
        guard let rootURL else { return }
        let indexURL = rootURL.appending(path: "index.json")
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(ClientCertificateIndex.self, from: data)
        else {
            return
        }
        certificates = index.certificates
    }

    private func write(
        _ data: Data,
        fileName: String,
        id: UUID,
        update: (inout ClientCertificate) -> Void
    ) {
        guard let index = certificates.firstIndex(where: { $0.id == id }) else { return }
        let directory = itemDirectory(for: id)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appending(path: fileName), options: .atomic)
        } catch {
            return
        }
        update(&certificates[index])
        persistNow()
    }

    private func readFile(_ fileName: String?, id: UUID) throws -> Data {
        guard let fileName else { throw ClientIdentityError.missingMaterial }
        let url = itemDirectory(for: id).appending(path: fileName)
        guard let data = try? Data(contentsOf: url) else {
            throw ClientIdentityError.missingMaterial
        }
        return data
    }

    private func itemDirectory(for id: UUID) -> URL {
        (rootURL ?? FileManager.default.temporaryDirectory)
            .appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    private func removeDirectory(for id: UUID) {
        try? fileManager.removeItem(at: itemDirectory(for: id))
    }

    private func pemCertificate(from der: Data) -> Data? {
        let base64 = der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return Data("-----BEGIN CERTIFICATE-----\n\(base64)\n-----END CERTIFICATE-----\n".utf8)
    }

    private static func defaultRootURL() -> URL? {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return appSupport.appending(path: "Fastpost/certificates", directoryHint: .isDirectory)
    }

    private static let crtFileName = "certificate.crt"
    private static let keyFileName = "private.key"
    private static let pfxFileName = "identity.pfx"
}

extension ClientCertificateStore {
    static var preview: ClientCertificateStore {
        let store = ClientCertificateStore(loadsFromDisk: false)
        store.certificates = [
            ClientCertificate(
                host: "api.example.com",
                port: 443,
                kind: .pem,
                crtFileName: "certificate.crt",
                keyFileName: "private.key",
                crtDisplayName: "client.crt",
                keyDisplayName: "client.key"
            ),
            ClientCertificate(
                host: "secure.local",
                kind: .pfx,
                pfxFileName: "identity.pfx",
                pfxDisplayName: "client.p12"
            )
        ]
        return store
    }
}
