import SwiftUI

struct KeyValueTable: View {
    @Binding var rows: [KeyValueRow]
    var keyPlaceholder: LocalizedStringKey
    var valuePlaceholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($rows) { $row in
                KeyValueRowView(
                    row: $row,
                    keyPlaceholder: keyPlaceholder,
                    valuePlaceholder: valuePlaceholder
                ) {
                    rows.removeAll { $0.id == row.id }
                }
            }

            Button("Add", systemImage: "plus") {
                rows.append(KeyValueRow())
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct KeyValueRowView: View {
    @Binding var row: KeyValueRow
    var keyPlaceholder: LocalizedStringKey
    var valuePlaceholder: String
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("Enabled", isOn: $row.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help("Include this field")
            TextField(keyPlaceholder, text: $row.key)
                .textFieldStyle(.roundedBorder)
            VariableTextField(text: $row.value, placeholder: valuePlaceholder)
            Button("Remove", systemImage: "minus.circle", role: .destructive, action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
    }
}

#Preview {
    @Previewable @State var rows = [
        KeyValueRow(key: "Accept", value: "application/json"),
        KeyValueRow(key: "X-Debug", value: "1", isEnabled: false),
    ]
    KeyValueTable(rows: $rows, keyPlaceholder: "Header", valuePlaceholder: "Value")
        .environment(AppSession.preview)
        .padding()
        .frame(width: 560, height: 180)
}
