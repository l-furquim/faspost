import SwiftUI

struct CertificatesSettingsView: View {
    @Environment(ClientCertificateStore.self) private var store
    @State private var selection: UUID?
    @State private var pendingDeleteID: UUID?

    var body: some View {
        HSplitView {
            certificateList
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)

            CertificateEditorDetail(certificateID: selection)
                .frame(minWidth: 420)
        }
        .clipShape(.rect)
        .onAppear {
            if selection == nil {
                selection = store.certificates.first?.id
            }
        }
        .onChange(of: store.certificates.map(\.id)) { _, ids in
            if let selection, ids.contains(selection) { return }
            self.selection = ids.first
        }
        .confirmationDialog(
            "Delete Certificate?",
            isPresented: Binding(
                get: { pendingDeleteID != nil },
                set: { if !$0 { pendingDeleteID = nil } }
            ),
            presenting: pendingDeleteCertificate
        ) { certificate in
            Button("Delete", role: .destructive) {
                if selection == certificate.id {
                    selection = store.certificates.first { $0.id != certificate.id }?.id
                }
                store.delete(id: certificate.id)
                pendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteID = nil
            }
        } message: { certificate in
            Text("“\(certificate.listTitle)” will be removed from Fastpost.")
        }
    }

    private var certificateList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Client Certificates") {
                    ForEach(store.certificates) { certificate in
                        CertificateListRow(certificate: certificate)
                            .tag(certificate.id)
                            .contextMenu {
                                Button("Delete…", systemImage: "trash", role: .destructive) {
                                    pendingDeleteID = certificate.id
                                }
                            }
                    }
                }
            }
            .listStyle(.inset)

            Divider()
            HStack {
                Button("New Certificate", systemImage: "plus") {
                    let created = store.create()
                    selection = created.id
                }
                .help("New Certificate")
                Spacer(minLength: 0)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(10)
        }
    }

    private var pendingDeleteCertificate: ClientCertificate? {
        guard let pendingDeleteID else { return nil }
        return store.certificates.first { $0.id == pendingDeleteID }
    }
}

private struct CertificateListRow: View {
    let certificate: ClientCertificate

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.doc")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(certificate.listTitle)
                    .lineLimit(1)
                Text(certificate.listSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct CertificateEditorDetail: View {
    @Environment(ClientCertificateStore.self) private var store
    let certificateID: UUID?
    @State private var identityError: String?
    @State private var validationTask: Task<Void, Never>?

    var body: some View {
        if let certificate {
            Form {
                Section {
                    Text("Used automatically when a request host matches.")
                        .foregroundStyle(.secondary)
                    TextField("Host", text: hostBinding, prompt: Text("api.example.com"))
                    TextField("Port", text: portBinding, prompt: Text("Any"))
                    Picker("Type", selection: kindBinding) {
                        ForEach(ClientCertificateKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    Toggle("Enabled", isOn: enabledBinding)
                } header: {
                    Text(certificate.listTitle)
                } footer: {
                    Text(statusText)
                }

                Section("Files") {
                    switch certificate.kind {
                    case .pem:
                        CertificateFileDrop(
                            title: "Certificate",
                            emptyPrompt: "Drop a .crt, .cer, or .pem file",
                            displayName: certificate.crtDisplayName,
                            contentTypes: CertificateContentTypes.certificate,
                            pickerMessage: String(localized: "Choose a certificate file"),
                            onImport: { store.importFile($0.data, displayName: $0.displayName, role: .certificate, id: certificate.id) },
                            onClear: { store.clearFile(.certificate, id: certificate.id) }
                        )
                        CertificateFileDrop(
                            title: "Private Key",
                            emptyPrompt: "Drop a .key or .pem file, or paste the key",
                            displayName: certificate.keyDisplayName,
                            contentTypes: CertificateContentTypes.privateKey,
                            pickerMessage: String(localized: "Choose a private key"),
                            onImport: { store.importFile($0.data, displayName: $0.displayName, role: .privateKey, id: certificate.id) },
                            onClear: { store.clearFile(.privateKey, id: certificate.id) }
                        )
                    case .pfx:
                        CertificateFileDrop(
                            title: "PKCS#12",
                            emptyPrompt: "Drop a .pfx or .p12 file",
                            displayName: certificate.pfxDisplayName,
                            contentTypes: CertificateContentTypes.pkcs12,
                            pickerMessage: String(localized: "Choose a PKCS#12 file"),
                            onImport: { store.importFile($0.data, displayName: $0.displayName, role: .pkcs12, id: certificate.id) },
                            onClear: { store.clearFile(.pkcs12, id: certificate.id) }
                        )
                    }
                }

                Section {
                    RevealableSecureField("Password", text: passphraseBinding)
                } header: {
                    Text("Password")
                } footer: {
                    Text("Used for encrypted keys and PKCS#12 files. Fastpost does not remember whether the password is shown.")
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: validationToken) { _, _ in
                scheduleValidation()
            }
            .onAppear(perform: scheduleValidation)
        } else {
            ContentUnavailableView {
                Label("No Certificates", systemImage: "lock.doc")
            } description: {
                Text("Add a client certificate to use mTLS for matching hosts.")
            } actions: {
                Button("Add Certificate") {
                    store.create()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var certificate: ClientCertificate? {
        guard let certificateID else { return nil }
        return store.certificates.first { $0.id == certificateID }
    }

    private var hostBinding: Binding<String> {
        Binding(
            get: { certificate?.host ?? "" },
            set: { newValue in
                guard let certificateID else { return }
                store.setHost(newValue, id: certificateID)
            }
        )
    }

    private var portBinding: Binding<String> {
        Binding(
            get: {
                guard let port = certificate?.port else { return "" }
                return String(port)
            },
            set: { newValue in
                guard let certificateID else { return }
                let digits = newValue.filter(\.isNumber)
                if digits.isEmpty {
                    store.setPort(nil, id: certificateID)
                    return
                }
                guard let port = Int(digits), (1...65535).contains(port) else { return }
                store.setPort(port, id: certificateID)
            }
        )
    }

    private var kindBinding: Binding<ClientCertificateKind> {
        Binding(
            get: { certificate?.kind ?? .pem },
            set: { newValue in
                guard let certificateID else { return }
                store.setKind(newValue, id: certificateID)
            }
        )
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { certificate?.isEnabled ?? true },
            set: { newValue in
                guard let certificateID else { return }
                store.setEnabled(newValue, id: certificateID)
            }
        )
    }

    private var passphraseBinding: Binding<String> {
        Binding(
            get: { certificate?.passphrase ?? "" },
            set: { newValue in
                guard let certificateID else { return }
                store.setPassphrase(newValue, id: certificateID)
            }
        )
    }

    private var validationToken: String {
        guard let certificate else { return "" }
        return [
            certificate.id.uuidString,
            certificate.kind.rawValue,
            certificate.passphrase,
            certificate.crtDisplayName ?? "",
            certificate.keyDisplayName ?? "",
            certificate.pfxDisplayName ?? ""
        ].joined(separator: "|")
    }

    private var statusText: String {
        if let identityError {
            return identityError
        }
        guard let certificate else { return "" }
        switch certificate.kind {
        case .pem:
            if !certificate.hasCertificateFile {
                return String(localized: "Add a certificate")
            }
            if !certificate.hasKeyFile {
                return String(localized: "Add a key")
            }
        case .pfx:
            if !certificate.hasPKCS12File {
                return String(localized: "Add a PKCS#12 file")
            }
        }
        return String(localized: "Ready")
    }

    private func scheduleValidation() {
        validationTask?.cancel()
        identityError = nil
        guard let certificate, certificate.hasRequiredFiles else { return }
        validationTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            guard let material = try? store.material(for: certificate) else { return }
            do {
                _ = try ClientIdentityLoader.load(material: material, passphrase: certificate.passphrase)
                guard !Task.isCancelled else { return }
                identityError = nil
            } catch let error as ClientIdentityError {
                guard !Task.isCancelled else { return }
                identityError = error.transportMessage
            } catch {
                guard !Task.isCancelled else { return }
                identityError = error.localizedDescription
            }
        }
    }
}

#Preview {
    CertificatesSettingsView()
        .environment(ClientCertificateStore.preview)
        .frame(width: 780, height: 560)
}
