import AppKit

enum FolderPicker {
    static func present(
        message: String,
        confirmTitle: String,
        canCreateDirectories: Bool = true
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = canCreateDirectories
            panel.allowsMultipleSelection = false
            panel.treatsFilePackagesAsDirectories = true
            panel.message = message
            panel.prompt = confirmTitle

            let finish: (NSApplication.ModalResponse) -> Void = { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }

            if let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) {
                panel.beginSheetModal(for: window, completionHandler: finish)
            } else {
                panel.begin(completionHandler: finish)
            }
        }
    }
}
