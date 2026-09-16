import AppKit
import UniformTypeIdentifiers

enum FilePicker {
    static func present(
        message: String,
        confirmTitle: String,
        contentTypes: [UTType]
    ) async -> URL? {
        await presentURLs(
            message: message,
            confirmTitle: confirmTitle,
            contentTypes: contentTypes,
            allowsMultipleSelection: false
        ).first
    }

    static func presentURLs(
        message: String,
        confirmTitle: String,
        contentTypes: [UTType],
        allowsMultipleSelection: Bool
    ) async -> [URL] {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.canCreateDirectories = false
            panel.allowsMultipleSelection = allowsMultipleSelection
            panel.allowedContentTypes = contentTypes
            panel.message = message
            panel.prompt = confirmTitle

            let finish: (NSApplication.ModalResponse) -> Void = { response in
                continuation.resume(returning: response == .OK ? panel.urls : [])
            }

            if let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) {
                panel.beginSheetModal(for: window, completionHandler: finish)
            } else {
                panel.begin(completionHandler: finish)
            }
        }
    }

    static func read(_ url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try Data(contentsOf: url)
    }
}

enum CertificateContentTypes {
    static var certificate: [UTType] {
        unique([
            .x509Certificate,
            type("pem"),
            type("crt"),
            type("cer"),
            type("der")
        ])
    }

    static var privateKey: [UTType] {
        unique([
            type("pem"),
            type("key"),
            .utf8PlainText,
            .data
        ])
    }

    static var pkcs12: [UTType] {
        unique([
            .pkcs12,
            type("pfx"),
            type("p12")
        ])
    }

    private static func type(_ ext: String) -> UTType {
        UTType(filenameExtension: ext) ?? UTType(filenameExtension: ext, conformingTo: .data) ?? .data
    }

    private static func unique(_ types: [UTType]) -> [UTType] {
        var seen = Set<UTType>()
        return types.filter { seen.insert($0).inserted }
    }
}
