import SwiftUI

struct RevealableSecureField: View {
    enum Layout {
        case labeled
        case compact
    }

    private let title: LocalizedStringKey
    @Binding private var text: String
    private var usesVariables = false
    private var layout = Layout.labeled
    @State private var showSecret = false

    init(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        usesVariables: Bool = false,
        layout: Layout = .labeled
    ) {
        self.title = title
        self._text = text
        self.usesVariables = usesVariables
        self.layout = layout
    }

    var body: some View {
        switch layout {
        case .labeled:
            LabeledContent(title) {
                compactField
            }
        case .compact:
            compactField
                .accessibilityLabel(title)
        }
    }

    private var compactField: some View {
        HStack(spacing: 8) {
            field
            revealButton
        }
    }

    @ViewBuilder
    private var field: some View {
        if showSecret, usesVariables {
            VariableTextField(text: $text, placeholder: "")
        } else if showSecret {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
        } else {
            SecureField("", text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var revealButton: some View {
        Button {
            showSecret.toggle()
        } label: {
            Image(systemName: showSecret ? "eye.slash" : "eye")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(showSecret ? "Hide" : "Show")
        .accessibilityLabel(showSecret ? "Hide" : "Show")
    }
}

#Preview {
    @Previewable @State var token = "secret-token"
    Form {
        RevealableSecureField("Token", text: $token, usesVariables: true)
        RevealableSecureField("Password", text: $token)
        RevealableSecureField("Value", text: $token, usesVariables: true, layout: .compact)
    }
    .formStyle(.grouped)
    .environment(AppSession.preview)
    .frame(width: 420)
}
