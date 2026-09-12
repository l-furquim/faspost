import SwiftUI

struct AuthEditorView: View {
    @Binding var auth: RequestAuth

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Type", selection: $auth.kind) {
                ForEach(AuthKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 240, alignment: .leading)

            switch auth.kind {
            case .none:
                Text("This request will be sent without an Authorization header.")
                    .foregroundStyle(.secondary)
            case .basic:
                Form {
                    RevealableSecureField("Username", text: $auth.username, usesVariables: true)
                    RevealableSecureField("Password", text: $auth.password, usesVariables: true)
                }
                .formStyle(.grouped)
            case .bearer:
                Form {
                    RevealableSecureField("Token", text: $auth.token, usesVariables: true)
                }
                .formStyle(.grouped)
            case .apiKey:
                Form {
                    LabeledContent("Key") {
                        VariableTextField(text: $auth.apiKeyName, placeholder: "")
                    }
                    RevealableSecureField("Value", text: $auth.apiKeyValue, usesVariables: true)
                    Picker("Add to", selection: $auth.apiKeyLocation) {
                        ForEach(APIKeyLocation.allCases) { location in
                            Text(location.title).tag(location)
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview("Basic") {
    @Previewable @State var auth = RequestAuth.basic(username: "user", password: "secret")
    AuthEditorView(auth: $auth)
        .environment(AppSession.preview)
        .padding()
        .frame(width: 480, height: 240)
}

#Preview("Bearer") {
    @Previewable @State var auth = RequestAuth.bearer(token: "secret")
    AuthEditorView(auth: $auth)
        .environment(AppSession.preview)
        .padding()
        .frame(width: 480, height: 240)
}
