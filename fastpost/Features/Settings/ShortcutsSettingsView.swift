import AppKit
import SwiftUI

struct ShortcutsSettingsView: View {
    @Environment(KeybindingStore.self) private var keybindings

    var body: some View {
        Form {
            Section {
                ForEach(AppCommandCatalog.all) { command in
                    LabeledContent {
                        ShortcutRecorderField(commandID: command.id)
                    } label: {
                        Label(command.title, systemImage: command.systemImage)
                    }
                }
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Shortcuts apply immediately. ⌘C, ⌘V, ⌘X, ⌘A, ⌘Z, and ⌘Q stay reserved for the system.")
            }

            Section {
                Button("Reset All Shortcuts") {
                    keybindings.resetAll()
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520)
    }
}

private struct ShortcutRecorderField: View {
    let commandID: AppCommandID
    @Environment(KeybindingStore.self) private var keybindings
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 8) {
            ShortcutRecorderRepresentable(isRecording: $isRecording) { binding in
                _ = keybindings.set(binding, for: commandID)
                isRecording = false
            } onCancel: {
                isRecording = false
            }
            .frame(width: 148, height: 24)
            .overlay {
                Text(isRecording ? "Type Shortcut" : (keybindings.glyphs(for: commandID) ?? "None"))
                    .font(.body.monospaced())
                    .foregroundStyle(isRecording ? Color.accentColor : .primary)
                    .allowsHitTesting(false)
            }
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onTapGesture {
                isRecording = true
            }

            if keybindings.isCustomized(commandID) {
                Button("Reset") {
                    keybindings.reset(commandID)
                    isRecording = false
                }
                .controlSize(.small)
            }
        }
    }
}

private struct ShortcutRecorderRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onCapture: (Keybinding) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ view: ShortcutRecorderNSView, context: Context) {
        view.onCapture = onCapture
        view.onCancel = onCancel
        view.isRecording = isRecording
        if isRecording {
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
            }
        }
    }
}

final class ShortcutRecorderNSView: NSView {
    var isRecording = false
    var onCapture: ((Keybinding) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        if let binding = Keybinding(event: event) {
            onCapture?(binding)
        }
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            onCancel?()
        }
        return super.resignFirstResponder()
    }
}

#Preview {
    ShortcutsSettingsView()
        .environment(KeybindingStore.preview)
        .frame(width: 560, height: 640)
}
