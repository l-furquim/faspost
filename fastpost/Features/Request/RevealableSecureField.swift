import SwiftUI

struct RevealableSecureField: View {
    private let title: LocalizedStringKey
    @Binding private var text: String
    private var usesVariables = false
    @State private var showSecret = false

    init(_ title: LocalizedStringKey, text: Binding<String>, usesVariables: Bool = false) {
        self.title = title
        self._text = text
        self.usesVariables = usesVariables
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                field
                revealButton
            }
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
    }
    .formStyle(.grouped)
    .environment(AppSession.preview)
    .frame(width: 420)
}
