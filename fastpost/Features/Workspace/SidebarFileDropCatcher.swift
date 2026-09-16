import AppKit
import SwiftUI

/// Intercepts Finder file-URL drags over the sidebar without stealing in-app item reorders or clicks.
struct SidebarFileDropCatcher: NSViewRepresentable {
    @Binding var isTargeted: Bool
    var onDrop: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isTargeted: $isTargeted, onDrop: onDrop)
    }

    func makeNSView(context: Context) -> FileDropCatcherView {
        let view = FileDropCatcherView()
        view.coordinator = context.coordinator
        view.registerForDraggedTypes(FileDropCatcherView.draggedTypes)
        return view
    }

    func updateNSView(_ nsView: FileDropCatcherView, context: Context) {
        context.coordinator.isTargeted = $isTargeted
        context.coordinator.onDrop = onDrop
        nsView.coordinator = context.coordinator
        nsView.registerForDraggedTypes(FileDropCatcherView.draggedTypes)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FileDropCatcherView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite else {
            return nil
        }
        return CGSize(width: max(width, 1), height: max(height, 1))
    }

    final class Coordinator {
        var isTargeted: Binding<Bool>
        var onDrop: ([URL]) -> Void

        init(isTargeted: Binding<Bool>, onDrop: @escaping ([URL]) -> Void) {
            self.isTargeted = isTargeted
            self.onDrop = onDrop
        }

        func setTargeted(_ value: Bool) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isTargeted.wrappedValue != value else { return }
                self.isTargeted.wrappedValue = value
            }
        }

        func deliver(_ urls: [URL]) {
            DispatchQueue.main.async { [weak self] in
                self?.onDrop(urls)
            }
        }
    }
}

final class FileDropCatcherView: NSView {
    static let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    static let draggedTypes: [NSPasteboard.PasteboardType] = [.fileURL, filenamesType]

    weak var coordinator: SidebarFileDropCatcher.Coordinator?
    private var isHandlingFileDrag = false
    private var lastHandledChangeCount = NSPasteboard(name: .drag).changeCount

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes(Self.draggedTypes)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isHandlingFileDrag { return self }

        if let type = NSApp.currentEvent?.type {
            switch type {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown,
                 .leftMouseUp, .rightMouseUp, .otherMouseUp,
                 .scrollWheel, .magnify, .smartMagnify, .swipe:
                return nil
            default:
                break
            }
        }

        let pasteboard = NSPasteboard(name: .drag)
        guard hasFileURL(pasteboard) else { return nil }
        guard pasteboard.changeCount != lastHandledChangeCount else { return nil }
        return self
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFileURL(sender.draggingPasteboard) else { return [] }
        isHandlingFileDrag = true
        coordinator?.setTargeted(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFileURL(sender.draggingPasteboard) else {
            finishDrag()
            return []
        }
        isHandlingFileDrag = true
        coordinator?.setTargeted(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        finishDrag()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        lastHandledChangeCount = sender.draggingPasteboard.changeCount
        finishDrag()
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        if let sender {
            lastHandledChangeCount = sender.draggingPasteboard.changeCount
        }
        finishDrag()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hasFileURL(sender.draggingPasteboard)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        lastHandledChangeCount = sender.draggingPasteboard.changeCount
        finishDrag()
        guard !urls.isEmpty else { return false }
        coordinator?.deliver(urls)
        return true
    }

    private func finishDrag() {
        isHandlingFileDrag = false
        coordinator?.setTargeted(false)
    }

    private func hasFileURL(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: Self.draggedTypes) != nil
            || pasteboard.types?.contains(.fileURL) == true
            || pasteboard.types?.contains(Self.filenamesType) == true
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        let pasteboard = sender.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? []
        var urls: [URL] = objects.compactMap { object in
            if let url = object as? URL {
                return url
            }
            if let nsURL = object as? NSURL {
                return nsURL as URL
            }
            return nil
        }
        if urls.isEmpty, let items = pasteboard.pasteboardItems {
            urls = items.compactMap { item in
                guard let raw = item.string(forType: .fileURL) else { return nil }
                if let url = URL(string: raw), url.isFileURL { return url }
                if raw.hasPrefix("/") { return URL(fileURLWithPath: raw) }
                return nil
            }
        }
        if urls.isEmpty, let paths = pasteboard.propertyList(forType: Self.filenamesType) as? [String] {
            urls = paths.map { URL(fileURLWithPath: $0) }
        }
        return urls.filter(\.isFileURL)
    }
}
