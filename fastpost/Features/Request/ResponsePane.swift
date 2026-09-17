import AppKit
import SwiftUI

struct ResponsePane: View {
    let state: RequestRunState
    var scriptResult: PostResponseResult? = nil

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
                ReceivedResponseView(exchange: exchange, scriptResult: scriptResult)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ReceivedResponseView: View {
    let exchange: HTTPExchange
    var scriptResult: PostResponseResult?
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
            case .scripts:
                ResponseScriptsView(result: scriptResult)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private enum ResponseSection: String, CaseIterable, Identifiable {
    case body, headers, cookies, scripts

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .body: "Body"
        case .headers: "Headers"
        case .cookies: "Cookies"
        case .scripts: "Scripts"
        }
    }

    var systemImage: String {
        switch self {
        case .body: "doc.plaintext"
        case .headers: "list.bullet"
        case .cookies: "circle.hexagongrid.fill"
        case .scripts: "hammer"
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

private struct ResponseScriptsView: View {
    @Environment(\.appTheme) private var theme
    var result: PostResponseResult?

    var body: some View {
        if let result, !result.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !result.extractorResults.isEmpty {
                        resultSection("Extractors") {
                            ForEach(result.extractorResults) { extractor in
                                labeledResult(
                                    title: extractor.variableKey,
                                    detail: extractor.value ?? extractor.message,
                                    success: extractor.isSuccess
                                )
                            }
                        }
                    }

                    if !result.tests.isEmpty {
                        resultSection("Tests") {
                            ForEach(result.tests) { test in
                                labeledResult(
                                    title: test.name,
                                    detail: test.message ?? (test.passed ? "Passed" : "Failed"),
                                    success: test.passed
                                )
                            }
                        }
                    }

                    if !result.logs.isEmpty {
                        resultSection("Console") {
                            ForEach(result.logs) { line in
                                Text(line.text)
                                    .font(.body.monospaced())
                                    .foregroundStyle(logColor(line.level))
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    if let errorMessage = result.errorMessage {
                        resultSection("Error") {
                            Text(errorMessage)
                                .font(.body.monospaced())
                                .foregroundStyle(theme.status.color(for: .clientError))
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                "No Scripts",
                systemImage: "hammer",
                description: Text("Add extractors or a test script, then send the request.")
            )
        }
    }

    private func resultSection(_ title: LocalizedStringResource, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func labeledResult(title: String, detail: String, success: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(theme.status.color(for: success ? .success : .clientError))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func logColor(_ level: ScriptLogLine.Level) -> Color {
        switch level {
        case .log: theme.syntax.text
        case .warn: theme.status.color(for: .redirect)
        case .error: theme.status.color(for: .clientError)
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
    ResponsePane(
        state: RequestRuntime.preview.states["preview-ok"] ?? .idle,
        scriptResult: RequestRuntime.preview.scriptResults["preview-ok"]
    )
        .environment(\.appTheme, .default)
        .frame(width: 640, height: 320)
}
