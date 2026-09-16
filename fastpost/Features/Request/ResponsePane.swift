import AppKit
import SwiftUI

struct ResponsePane: View {
    let state: RequestRunState

    var body: some View {
        ZStack {
            switch state {
            case .idle:
                ContentUnavailableView(
                    "No Response",
                    systemImage: "bolt.horizontal",
                    description: Text("Send a request to see the response.")
                )
            case .sending:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Sending…")
                        .foregroundStyle(.secondary)
                }
            case .failed(let failure):
                ContentUnavailableView(
                    failure.title,
                    systemImage: failure.systemImage,
                    description: Text(failure.message)
                )
            case .received(let exchange):
                ReceivedResponseView(exchange: exchange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ReceivedResponseView: View {
    let exchange: HTTPExchange
    @State private var pane = ResponseSection.body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponseStatusBar(exchange: exchange)
            GlassSegmentedPicker(selection: $pane, accessibilityLabel: "Section")

            switch pane {
            case .body:
                ResponseBodyView(exchange: exchange)
            case .headers:
                ResponseHeadersView(headers: exchange.headers)
            case .cookies:
                ResponseCookiesView(cookies: exchange.cookies)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private enum ResponseSection: String, CaseIterable, Identifiable {
    case body, headers, cookies

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .body: "Body"
        case .headers: "Headers"
        case .cookies: "Cookies"
        }
    }

    var systemImage: String {
        switch self {
        case .body: "doc.plaintext"
        case .headers: "list.bullet"
        case .cookies: "circle.hexagongrid.fill"
        }
    }
}

extension ResponseSection: GlassSegmentOption {}

struct ResponseStatusBar: View {
    let exchange: HTTPExchange
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Text(exchange.statusDisplay)
                .font(.headline.monospaced())
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.12), in: .rect(cornerRadius: 6))

            Text("\(exchange.durationMilliseconds) ms")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help("Response time")

            Text(Int64(exchange.byteCount), format: .byteCount(style: .file))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help("Response size")

            if exchange.showsFinalURL {
                Text(exchange.finalURL.absoluteString)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(exchange.finalURL.absoluteString)
            }

            Spacer(minLength: 0)
        }
    }

    private var statusColor: Color {
        theme.status.color(for: exchange.statusFamily)
    }
}

private struct ResponseBodyView: View {
    let exchange: HTTPExchange

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if exchange.isTruncated {
                Text("Preview truncated to the first megabyte.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch exchange.body {
            case .empty:
                ContentUnavailableView(
                    "Empty Body",
                    systemImage: "doc",
                    description: Text("The server returned no content.")
                )
            case .json(let text):
                bodyEditor(text, language: .json)
            case .text(let text):
                bodyEditor(text, language: .plain)
            case .binary(let mime):
                ContentUnavailableView(
                    "Binary Response",
                    systemImage: "doc.zipper",
                    description: Text(binaryDescription(mime: mime))
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func bodyEditor(_ text: String, language: CodeLanguage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer(minLength: 0)
                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderless)
            }
            CodeEditor(text: .constant(text), isEditable: false, language: language)
        }
    }

    private func binaryDescription(mime: String) -> String {
        let size = ByteCountFormatStyle(style: .file).format(Int64(exchange.byteCount))
        return "\(mime) · \(size)"
    }
}

private struct ResponseHeadersView: View {
    let headers: [HTTPHeader]

    var body: some View {
        if headers.isEmpty {
            ContentUnavailableView(
                "No Headers",
                systemImage: "list.bullet",
                description: Text("The server did not return any headers.")
            )
        } else {
            Table(headers.enumerated().map { HeaderRow(id: "\($0.offset)-\($0.element.key)", header: $0.element) }) {
                TableColumn("Header") { Text($0.header.key) }
                TableColumn("Value") { Text($0.header.value) }
            }
            .tableStyle(.inset)
        }
    }
}

private struct HeaderRow: Identifiable {
    var id: String
    var header: HTTPHeader
}

private struct ResponseCookiesView: View {
    let cookies: [ResponseCookie]

    var body: some View {
        if cookies.isEmpty {
            ContentUnavailableView(
                "No Cookies",
                systemImage: "circle.dashed",
                description: Text("The response did not include Set-Cookie.")
            )
        } else {
            Table(cookies) {
                TableColumn("Name") { Text($0.name) }
                TableColumn("Value") { Text($0.value) }
                TableColumn("Domain") { Text($0.domain) }
                TableColumn("Path") { Text($0.path) }
            }
            .tableStyle(.inset)
        }
    }
}

#Preview("Idle") {
    ResponsePane(state: .idle)
        .frame(width: 640, height: 280)
}

#Preview("Timeout") {
    ResponsePane(state: .failed(.timeout))
        .frame(width: 640, height: 280)
}

#Preview("200") {
    ResponsePane(state: RequestRuntime.preview.states["preview-ok"] ?? .idle)
        .frame(width: 640, height: 320)
}
