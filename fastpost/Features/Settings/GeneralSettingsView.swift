import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(AppPreferenceStorage.timeoutSeconds) private var timeoutSeconds = RequestPreferences.default.timeoutSeconds
    @AppStorage(AppPreferenceStorage.maxResponseMB) private var maxResponseMB = RequestPreferences.default.maxResponseMB
    @AppStorage(AppPreferenceStorage.verifySSL) private var verifySSL = RequestPreferences.default.verifySSL
    @AppStorage(AppPreferenceStorage.followRedirects) private var followRedirects = RequestPreferences.default.followRedirects
    @AppStorage(AppPreferenceStorage.sendNoCache) private var sendNoCache = RequestPreferences.default.sendNoCache
    @AppStorage(AppPreferenceStorage.httpVersion) private var httpVersion = RequestPreferences.default.httpVersion.rawValue
    @AppStorage(AppPreferenceStorage.encodeURL) private var encodeURL = RequestPreferences.default.encodeURL
    @AppStorage(AppPreferenceStorage.useCookieJar) private var useCookieJar = RequestPreferences.default.useCookieJar
    @AppStorage(AppPreferenceStorage.maxRedirects) private var maxRedirects = RequestPreferences.default.maxRedirects
    @AppStorage(AppPreferenceStorage.preserveMethodOnRedirect) private var preserveMethodOnRedirect = RequestPreferences.default.preserveMethodOnRedirect
    @AppStorage(AppPreferenceStorage.followAuthorizationHeader) private var followAuthorizationHeader = RequestPreferences.default.followAuthorizationHeader
    @AppStorage(AppPreferenceStorage.removeRefererOnRedirect) private var removeRefererOnRedirect = RequestPreferences.default.removeRefererOnRedirect
    @AppStorage(AppPreferenceStorage.tlsMinimum) private var tlsMinimum = RequestPreferences.default.tlsMinimum.rawValue

    var body: some View {
        Form {
            Section {
                LabeledContent("Timeout") {
                    HStack(spacing: 6) {
                        TextField("Seconds", text: numericBinding($timeoutSeconds))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 96)
                        Text("sec")
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Max Response Size") {
                    HStack(spacing: 6) {
                        TextField("MB", text: numericBinding($maxResponseMB))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 96)
                        Text("MB")
                            .foregroundStyle(.secondary)
                    }
                }
                Picker("HTTP Version", selection: $httpVersion) {
                    ForEach(HTTPVersionPreference.allCases) { version in
                        Text(version.title).tag(version.rawValue)
                    }
                }
                Toggle("Encode URL Automatically", isOn: $encodeURL)
            } header: {
                Text("Request")
            } footer: {
                Text("Use 0 for timeout or size to remove the limit. HTTP/3 is a hint; the system still chooses the protocol.")
            }

            Section {
                Toggle("Follow Redirects", isOn: $followRedirects)
                LabeledContent("Maximum Redirects") {
                    TextField("Count", text: integerBinding($maxRedirects))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 96)
                        .disabled(!followRedirects)
                }
                Toggle("Preserve Method on Redirect", isOn: $preserveMethodOnRedirect)
                    .disabled(!followRedirects)
                Toggle("Send Authorization Header on Cross-Host Redirect", isOn: $followAuthorizationHeader)
                    .disabled(!followRedirects)
                Toggle("Remove Referer on Redirect", isOn: $removeRefererOnRedirect)
                    .disabled(!followRedirects)
            } header: {
                Text("Redirects")
            } footer: {
                Text("Use 0 for an unlimited redirect count.")
            }

            Section {
                Toggle("SSL Certificate Verification", isOn: $verifySSL)
                Picker("Minimum TLS Version", selection: $tlsMinimum) {
                    ForEach(TLSMinimumVersion.allCases) { version in
                        Text(version.title).tag(version.rawValue)
                    }
                }
            } header: {
                Text("Security")
            }

            Section {
                Toggle("Use Cookie Jar", isOn: $useCookieJar)
            } header: {
                Text("Cookies")
            } footer: {
                Text("Cookies stay in memory for this app session.")
            }

            Section("Headers") {
                Toggle("Send no-cache Header", isOn: $sendNoCache)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520)
    }

    private func numericBinding(_ value: Binding<Double>) -> Binding<String> {
        Binding(
            get: {
                value.wrappedValue.rounded() == value.wrappedValue
                    ? String(Int(value.wrappedValue))
                    : String(value.wrappedValue)
            },
            set: { newValue in
                let filtered = newValue.filter { $0.isNumber || $0 == "." }
                if filtered.isEmpty { return }
                if let parsed = Double(filtered) {
                    value.wrappedValue = parsed
                }
            }
        )
    }

    private func integerBinding(_ value: Binding<Int>) -> Binding<String> {
        Binding(
            get: { String(value.wrappedValue) },
            set: { newValue in
                let filtered = newValue.filter(\.isNumber)
                if filtered.isEmpty { return }
                if let parsed = Int(filtered) {
                    value.wrappedValue = parsed
                }
            }
        )
    }
}

#Preview {
    GeneralSettingsView()
        .frame(width: 520, height: 720)
}
