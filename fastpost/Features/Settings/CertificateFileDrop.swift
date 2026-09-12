import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CertificateImport: Equatable {
    var data: Data
    var displayName: String
}

struct CertificateFileDrop: View {
    let title: LocalizedStringKey
    let emptyPrompt: LocalizedStringKey
    let displayName: String?
    let contentTypes: [UTType]
    let pickerMessage: String
    let onImport: (CertificateImport) -> Void
    let onClear: () -> Void

    @State private var isTargeted = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer(minLength: 0)
                if displayName != nil {
                    Button("Remove", systemImage: "xmark.circle.fill") {
                        onClear()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove")
                }
            }

            HStack(alignment: .center, spacing: 10) {
                Image(systemName: displayName == nil ? "plus.circle" : "doc")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Group {
                        if let displayName {
                            Text(displayName)
                        } else {
                            Text(emptyPrompt)
                        }
                    }
                    .foregroundStyle(displayName == nil ? .secondary : .primary)
                    .lineLimit(1)
                    Text("Choose, drop, or paste")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Button("Choose…") {
                    Task { await pickFile() }
                }
                PasteButton(payloadType: String.self) { strings in
                    if let string = strings.first {
                        importPastedString(string)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isTargeted || isFocused ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isTargeted || isFocused ? Color.accentColor : Color.primary.opacity(0.12),
                        style: StrokeStyle(lineWidth: 1, dash: displayName == nil ? [5, 4] : [])
                    )
            }
            .focusable()
            .focused($isFocused)
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                return importURL(url)
            } isTargeted: { targeted in
                if isTargeted != targeted {
                    isTargeted = targeted
                }
            }
            .dropDestination(for: String.self) { strings, _ in
                guard let string = strings.first else { return false }
                importPastedString(string)
                return true
            }
            .onPasteCommand(of: [.utf8PlainText, .fileURL, .data]) { _ in
                pasteFromPasteboard()
            }
            .accessibilityLabel(title)
            .accessibilityHint(displayName ?? String(localized: "Choose, drop, or paste a file"))
        }
    }

    private func pickFile() async {
        guard let url = await FilePicker.present(
            message: pickerMessage,
            confirmTitle: String(localized: "Choose"),
            contentTypes: contentTypes
        ) else {
            return
        }
        _ = importURL(url)
    }

    @discardableResult
    private func importURL(_ url: URL) -> Bool {
        do {
            let data = try FilePicker.read(url)
            onImport(CertificateImport(data: data, displayName: url.lastPathComponent))
            return true
        } catch {
            return false
        }
    }

    private func importPastedString(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        if let decoded = Data(base64Encoded: trimmed.filter { !$0.isWhitespace }), !decoded.isEmpty, !PEMParser.looksLikePEM(data) {
            onImport(CertificateImport(data: decoded, displayName: String(localized: "Pasted File")))
            return
        }
        onImport(CertificateImport(data: data, displayName: String(localized: "Pasted File")))
    }

    private func pasteFromPasteboard() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first {
            _ = importURL(url)
            return
        }
        if let string = pasteboard.string(forType: .string) {
            importPastedString(string)
            return
        }
        if let data = pasteboard.data(forType: .init("public.data")), !data.isEmpty {
            onImport(CertificateImport(data: data, displayName: String(localized: "Pasted File")))
        }
    }
}

#Preview {
    Form {
        CertificateFileDrop(
            title: "Certificate",
            emptyPrompt: "Drop a .crt or .pem file",
            displayName: nil,
            contentTypes: CertificateContentTypes.certificate,
            pickerMessage: "Choose a certificate file",
            onImport: { _ in },
            onClear: {}
        )
        CertificateFileDrop(
            title: "Private Key",
            emptyPrompt: "Drop a .key or .pem file",
            displayName: "client.key",
            contentTypes: CertificateContentTypes.privateKey,
            pickerMessage: "Choose a private key",
            onImport: { _ in },
            onClear: {}
        )
    }
    .formStyle(.grouped)
    .frame(width: 420, height: 280)
}
