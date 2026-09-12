import SwiftUI

struct RequestEditorView: View {
    @Environment(AppSession.self) private var session
    @Environment(RequestRuntime.self) private var runtime
    @State private var pane = RequestPane.params

    var body: some View {
        if let item = session.selectedItem, item.request != nil {
            RequestEditorContent(item: item, pane: $pane)
        } else if session.selectedItem?.isFolder == true {
            ContentUnavailableView(
                "Folder Selected",
                systemImage: "folder",
                description: Text("Select a request, or create one inside this folder.")
            )
        } else {
            ContentUnavailableView(
                "No Request Selected",
                systemImage: "bolt.horizontal",
                description: Text("Choose a request from the sidebar, or create a new one.")
            )
        }
    }
}

enum RequestPane: String, CaseIterable, Identifiable {
    case params
    case authorization
    case headers
    case body

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .params: "Params"
        case .authorization: "Authorization"
        case .headers: "Headers"
        case .body: "Body"
        }
    }

    var systemImage: String {
        switch self {
        case .params: "slider.horizontal.3"
        case .authorization: "lock.fill"
        case .headers: "list.bullet"
        case .body: "doc.plaintext"
        }
    }
}

extension RequestPane: GlassSegmentOption {}
extension RequestBodyMode: GlassSegmentOption {}

private struct RequestEditorContent: View {
    @Environment(AppSession.self) private var session
    @Environment(RequestRuntime.self) private var runtime
    @Environment(ClientCertificateStore.self) private var certificates
    let item: CollectionItem
    @Binding var pane: RequestPane
    @SceneStorage("request.responsePaneHeight") private var responsePaneHeight = 280.0
    @State private var headerRows: [KeyValueRow] = []
    @State private var paramRows: [KeyValueRow] = []

    var body: some View {
        @Bindable var session = session
        @Bindable var runtime = runtime

        PersistentVSplitView(bottomHeight: $responsePaneHeight) {
            VStack(alignment: .leading, spacing: 12) {
                Text(item.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Picker("Method", selection: $session.selectedRequestMethod) {
                            ForEach(HTTPMethod.allCases) { method in
                                Text(method.rawValue).tag(method)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)

                        VariableTextField(
                            text: $session.selectedRequestURL,
                            placeholder: "https://api.example.com/path",
                            onSubmit: syncParamRowsFromURL
                        )

                        sendButton
                    }

                    if let matchedCertificate {
                        Label("Client certificate for \(matchedCertificate.host)", systemImage: "lock.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GlassSegmentedPicker(selection: $pane, accessibilityLabel: "Section")

                requestSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(20)
        } bottom: {
            ResponsePane(state: runtime.state(for: item.id))
        }
        .onAppear(perform: reloadDrafts)
        .onChange(of: item.id) { _, _ in
            reloadDrafts()
        }
        .onChange(of: headerRows) { _, newRows in
            session.selectedHeaders = newRows.map(\.header)
        }
        .onChange(of: paramRows) { _, newRows in
            let params = newRows.map(\.queryParam)
            if session.selectedQueryParams != params {
                session.selectedQueryParams = params
            }
        }
        .onChange(of: session.selectedRequestURL) { _, _ in
            guard pane == .params else { return }
            syncParamRowsFromURL()
        }
        .onChange(of: pane) { _, newPane in
            if newPane == .params {
                syncParamRowsFromURL()
            }
        }
    }

    @ViewBuilder
    private var requestSection: some View {
        @Bindable var session = session
        switch pane {
        case .params:
            KeyValueTable(rows: $paramRows, keyPlaceholder: "Parameter", valuePlaceholder: "Value")
        case .authorization:
            AuthEditorView(auth: $session.selectedAuth)
        case .headers:
            KeyValueTable(rows: $headerRows, keyPlaceholder: "Header", valuePlaceholder: "Value")
        case .body:
            RequestBodyEditor(itemID: item.id)
        }
    }

    private var sendButton: some View {
        Button(runtime.isSending(item.id) ? "Stop" : "Send") {
            toggleSend()
        }
        .appShortcut(.send)
        .buttonStyle(.borderedProminent)
        .tint(runtime.isSending(item.id) ? .red : .accentColor)
    }

    private var matchedCertificate: ClientCertificate? {
        guard let request = session.selectedRequest else { return nil }
        return certificates.match(rawURL: session.resolved(request).rawURL)
    }

    private func toggleSend() {
        guard let request = session.selectedRequest else { return }
        runtime.toggleSend(id: item.id, request: session.resolved(request))
    }

    private func reloadDrafts() {
        headerRows = session.selectedHeaders.map(KeyValueRow.init)
        if headerRows.isEmpty { headerRows = [KeyValueRow()] }
        applyParamsPreservingIDs(session.selectedQueryParams)
    }

    private func syncParamRowsFromURL() {
        let incoming = session.selectedQueryParams
        if incoming == paramRows.map(\.queryParam) { return }
        applyParamsPreservingIDs(incoming)
    }

    private func applyParamsPreservingIDs(_ params: [QueryParam]) {
        var next: [KeyValueRow] = []
        next.reserveCapacity(max(params.count, 1))
        for (index, param) in params.enumerated() {
            if paramRows.indices.contains(index) {
                var row = paramRows[index]
                let value = param.value ?? ""
                let isEnabled = param.disabled != true
                if row.key != param.key { row.key = param.key }
                if row.value != value { row.value = value }
                if row.isEnabled != isEnabled { row.isEnabled = isEnabled }
                next.append(row)
            } else {
                next.append(KeyValueRow(param))
            }
        }
        if next.isEmpty { next = [KeyValueRow()] }
        if next != paramRows {
            paramRows = next
        }
    }
}

private struct RequestBodyEditor: View {
    @Environment(AppSession.self) private var session
    let itemID: String
    @State private var formRows: [KeyValueRow] = []

    var body: some View {
        @Bindable var session = session

        VStack(alignment: .leading, spacing: 8) {
            GlassSegmentedPicker(selection: $session.selectedBodyMode, accessibilityLabel: "Body Type")

            Group {
                switch session.selectedBodyMode {
                case .none:
                    emptyBody
                case .raw:
                    CodeEditor(text: $session.selectedBodyJSON, language: .json)
                case .urlencoded:
                    KeyValueTable(rows: $formRows, keyPlaceholder: "Key", valuePlaceholder: "Value")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: reloadForm)
        .onChange(of: itemID) { _, _ in
            reloadForm()
        }
        .onChange(of: session.selectedBodyMode) { _, mode in
            if mode == .urlencoded {
                reloadForm()
            }
        }
        .onChange(of: formRows) { _, newRows in
            let params = newRows.map(\.queryParam)
            if session.selectedBodyForm != params {
                session.selectedBodyForm = params
            }
        }
    }

    private var emptyBody: some View {
        VStack(spacing: 6) {
            Image(systemName: "slash.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No Body")
                .font(.headline)
            Text("This request will be sent without a body.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reloadForm() {
        let params = session.selectedBodyForm
        if params == formRows.map(\.queryParam) { return }
        var next: [KeyValueRow] = []
        next.reserveCapacity(max(params.count, 1))
        for (index, param) in params.enumerated() {
            if formRows.indices.contains(index) {
                var row = formRows[index]
                let value = param.value ?? ""
                let isEnabled = param.disabled != true
                if row.key != param.key { row.key = param.key }
                if row.value != value { row.value = value }
                if row.isEnabled != isEnabled { row.isEnabled = isEnabled }
                next.append(row)
            } else {
                next.append(KeyValueRow(param))
            }
        }
        if next.isEmpty { next = [KeyValueRow()] }
        if next != formRows {
            formRows = next
        }
    }
}

#Preview {
    RequestEditorView()
        .environment(AppSession.preview)
        .environment(RequestRuntime.preview)
        .environment(ClientCertificateStore.preview)
        .environment(KeybindingStore.preview)
        .frame(width: 860, height: 640)
}
