import SwiftUI

struct EditorSettingsView: View {
    @AppStorage(AppPreferenceStorage.editorFontSize) private var fontSize = EditorPreferences.default.fontSize
    @AppStorage(AppPreferenceStorage.editorIndentSpaces) private var indentSpaces = EditorPreferences.default.indentSpaces

    var body: some View {
        Form {
            Section("Font") {
                Stepper(value: $fontSize, in: 10...22, step: 1) {
                    Text("\(Int(fontSize)) pt")
                }
            }

            Section("Indentation") {
                Picker("Spaces", selection: $indentSpaces) {
                    ForEach(EditorPreferences.indentOptions, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520)
    }
}

#Preview {
    EditorSettingsView()
        .frame(width: 440, height: 220)
}
