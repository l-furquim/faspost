import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage(AppearanceStorage.colorSchemeKey) private var colorSchemeRaw = ColorSchemePreference.system.rawValue
    @AppStorage(AppearanceStorage.themeIDKey) private var themeID = AppThemeID.default.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $colorSchemeRaw) {
                    ForEach(ColorSchemePreference.allCases) { preference in
                        Text(preference.title).tag(preference.rawValue)
                    }
                }
                .disabled(themeID != AppThemeID.default.rawValue)

                Picker("Theme", selection: $themeID) {
                    ForEach(AppThemeID.allCases) { theme in
                        Text(theme.title).tag(theme.rawValue)
                    }
                }
            } footer: {
                if themeID == AppThemeID.default.rawValue {
                    Text("Default keeps system window chrome and follows Appearance.")
                } else {
                    Text("Named themes restyle the whole app, including the sidebar, toolbar, and editors.")
                }
            }

            Section("Preview") {
                ThemePreview(theme: AppTheme.named(themeID))
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520)
    }
}

private struct ThemePreview: View {
    let theme: AppTheme

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("GET")
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(theme.method.get)
                Text("Health")
                    .font(.caption)
                    .foregroundStyle(theme.syntax.text)
            }
            .padding(12)
            .frame(width: 120, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(theme.chrome?.sidebar ?? theme.editorBackground)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text("POST")
                        .foregroundStyle(theme.method.post)
                    Text("DELETE")
                        .foregroundStyle(theme.method.delete)
                }
                .font(.caption.weight(.semibold).monospaced())

                HStack(spacing: 0) {
                    Text("{ ")
                        .foregroundStyle(theme.syntax.punctuation)
                    Text("\"ok\"")
                        .foregroundStyle(theme.syntax.key)
                    Text(": ")
                        .foregroundStyle(theme.syntax.punctuation)
                    Text("true")
                        .foregroundStyle(theme.syntax.keyword)
                    Text(" }")
                        .foregroundStyle(theme.syntax.punctuation)
                }
                .font(.body.monospaced())

                Text("{{baseUrl}}")
                    .font(.body.monospaced())
                    .foregroundStyle(theme.variable.resolved)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.chrome?.surface ?? theme.editorBackground)
        }
        .frame(minHeight: 120)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder((theme.chrome?.accent ?? Color.primary).opacity(0.2), lineWidth: 1)
        }
    }
}

#Preview {
    AppearanceSettingsView()
        .frame(width: 520, height: 360)
}
