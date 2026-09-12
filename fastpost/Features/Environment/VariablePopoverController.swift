import AppKit
import SwiftUI

@MainActor
final class VariablePopoverController: NSObject, NSPopoverDelegate {
    var onPickSuggestion: ((VariableSuggestion) -> Void)?
    var onAddToken: ((VariableToken) -> Void)?
    var onEditToken: ((VariableToken, String) -> Void)?

    /// Compatibility with the previous completion controller.
    var onPick: ((VariableSuggestion) -> Void)? {
        get { onPickSuggestion }
        set { onPickSuggestion = newValue }
    }

    private let tokenPopover = NSPopover()
    private let suggestionPopover = NSPopover()
    private let tokenModel = VariableTokenPopoverModel()
    private let suggestionModel = VariableSuggestionPopoverModel()
    private var tokenHost: NSHostingController<VariableTokenPopover>?
    private var suggestionHost: NSHostingController<VariableSuggestionPopover>?
    private var clickMonitor: Any?
    private weak var positioningView: NSView?

    override init() {
        super.init()
        configure(tokenPopover)
        configure(suggestionPopover)
        tokenHost = NSHostingController(
            rootView: VariableTokenPopover(
                model: tokenModel,
                onAdd: { [weak self] in self?.handleAddToken() },
                onEdit: { [weak self] value in self?.handleEditToken(value) }
            )
        )
        suggestionHost = NSHostingController(
            rootView: VariableSuggestionPopover(
                model: suggestionModel,
                onPick: { [weak self] item in
                    self?.onPickSuggestion?(item)
                    self?.hide()
                }
            )
        )
        tokenHost?.sizingOptions = [.intrinsicContentSize]
        suggestionHost?.sizingOptions = [.intrinsicContentSize]
        tokenPopover.contentViewController = tokenHost
        suggestionPopover.contentViewController = suggestionHost
    }

    var isVisible: Bool { suggestionPopover.isShown }
    var isShowingSuggestions: Bool { suggestionPopover.isShown }
    var isShown: Bool { tokenPopover.isShown || suggestionPopover.isShown }
    var shownTokenID: String? { tokenPopover.isShown ? tokenModel.token?.id : nil }

    var containsMouse: Bool {
        contains(screenPoint: NSEvent.mouseLocation)
    }

    var isEditingTokenValue: Bool {
        guard tokenPopover.isShown,
              let content = tokenPopover.contentViewController?.view,
              let responder = content.window?.firstResponder as? NSView
        else { return false }
        return responder === content || responder.isDescendant(of: content)
    }

    func showToken(
        _ token: VariableToken,
        relativeTo view: NSView,
        screenRect: NSRect,
        environmentName: String?,
        theme: AppTheme = .default
    ) {
        hideSuggestions()
        let changed = tokenModel.token?.id != token.id
        tokenModel.token = token
        tokenModel.environmentName = environmentName
        tokenModel.theme = theme
        if changed {
            tokenModel.draft = token.resolvedValue ?? ""
            tokenModel.added = token.isResolved
        }
        present(
            tokenPopover,
            relativeTo: Self.positioningRect(screenRect: screenRect, in: view),
            of: view,
            size: tokenSize
        )
    }

    func show(
        _ items: [VariableSuggestion],
        relativeTo view: NSView,
        caretScreen: NSPoint? = nil
    ) {
        showSuggestions(items, relativeTo: view, caretScreen: caretScreen)
    }

    func showSuggestions(
        _ items: [VariableSuggestion],
        relativeTo view: NSView,
        caretScreen: NSPoint? = nil
    ) {
        guard !items.isEmpty else {
            hideSuggestions()
            return
        }
        hideToken()
        if suggestionModel.selectedID == nil
            || !items.contains(where: { $0.id == suggestionModel.selectedID }) {
            suggestionModel.selectedID = items.first?.id
        }
        suggestionModel.items = items
        let height = min(CGFloat(items.count) * 28 + 8, 180)
        present(
            suggestionPopover,
            relativeTo: Self.positioningRect(screenOrigin: caretScreen, in: view),
            of: view,
            size: NSSize(width: 300, height: height)
        )
    }

    func moveSuggestion(by delta: Int) {
        moveSelection(by: delta)
    }

    func moveSelection(by delta: Int) {
        let items = suggestionModel.items
        guard !items.isEmpty else { return }
        let current = items.firstIndex(where: { $0.id == suggestionModel.selectedID }) ?? 0
        let next = min(max(current + delta, 0), items.count - 1)
        suggestionModel.selectedID = items[next].id
    }

    func confirmSuggestion() {
        confirmSelection()
    }

    func confirmSelection() {
        let items = suggestionModel.items
        guard let item = items.first(where: { $0.id == suggestionModel.selectedID }) ?? items.first else {
            return
        }
        onPickSuggestion?(item)
        hide()
    }

    func hideToken() {
        if tokenPopover.isShown {
            tokenPopover.performClose(nil)
        }
        if !suggestionPopover.isShown {
            removeClickMonitor()
        }
    }

    func hideSuggestions() {
        if suggestionPopover.isShown {
            suggestionPopover.performClose(nil)
        }
        suggestionModel.items = []
        suggestionModel.selectedID = nil
        if !tokenPopover.isShown {
            removeClickMonitor()
        }
    }

    func hide() {
        hideToken()
        hideSuggestions()
        positioningView = nil
        removeClickMonitor()
    }

    func contains(screenPoint: NSPoint) -> Bool {
        tokenPopover.contentViewController?.view.window?.frame.contains(screenPoint) == true
            || suggestionPopover.contentViewController?.view.window?.frame.contains(screenPoint) == true
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        false
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        true
    }

    func popoverDidClose(_ notification: Notification) {
        if !isShown {
            removeClickMonitor()
        }
    }

    private func configure(_ popover: NSPopover) {
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
    }

    private func present(_ popover: NSPopover, relativeTo rect: NSRect, of view: NSView, size: NSSize) {
        positioningView = view
        popover.animates = !popover.isShown
        popover.contentSize = size
        popover.show(relativeTo: rect, of: view, preferredEdge: .minY)
        installClickMonitor()
    }

    private var tokenSize: NSSize {
        NSSize(width: 292, height: tokenModel.showsValue ? 122 : 150)
    }

    private func handleAddToken() {
        guard let token = tokenModel.token else { return }
        tokenModel.added = true
        tokenModel.draft = ""
        onAddToken?(token)
        if tokenPopover.isShown {
            tokenPopover.contentSize = tokenSize
        }
    }

    private func handleEditToken(_ value: String) {
        guard let token = tokenModel.token else { return }
        onEditToken?(token, value)
    }

    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.dismissIfClickOutside()
            return event
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    private func dismissIfClickOutside() {
        let screen = NSEvent.mouseLocation
        if contains(screenPoint: screen) { return }
        if let view = positioningView, Self.view(view, containsScreenPoint: screen) {
            return
        }
        hide()
    }

    private static func view(_ view: NSView, containsScreenPoint screen: NSPoint) -> Bool {
        guard let window = view.window else { return false }
        let windowPoint = window.convertFromScreen(NSRect(origin: screen, size: .zero)).origin
        return view.bounds.contains(view.convert(windowPoint, from: nil))
    }

    private static func positioningRect(screenRect: NSRect, in view: NSView) -> NSRect {
        guard let window = view.window else { return view.bounds }
        var local = view.convert(window.convertFromScreen(screenRect), from: nil)
        if local.width < 8 { local.size.width = 8 }
        if local.height < 8 { local.size.height = max(view.bounds.height, 16) }
        return local
    }

    private static func positioningRect(screenOrigin: NSPoint?, in view: NSView) -> NSRect {
        guard let screenOrigin else { return view.bounds }
        return positioningRect(
            screenRect: NSRect(origin: screenOrigin, size: NSSize(width: 2, height: 16)),
            in: view
        )
    }
}

@Observable
@MainActor
final class VariableTokenPopoverModel {
    var token: VariableToken?
    var environmentName: String?
    var draft = ""
    var added = false
    var theme = AppTheme.default

    var showsValue: Bool {
        token?.isResolved == true || added
    }

    var statusTitle: String {
        if added, token?.origin == nil {
            return environmentName ?? "Collection"
        }
        return token?.origin?.title ?? "Unresolved"
    }
}

@Observable
@MainActor
final class VariableSuggestionPopoverModel {
    var items: [VariableSuggestion] = []
    var selectedID: String?
}

private struct VariableTokenPopover: View {
    @Bindable var model: VariableTokenPopoverModel
    var onAdd: () -> Void
    var onEdit: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("{{\(model.token?.name ?? "")}}")
                .font(.headline.monospaced())
            Text(model.statusTitle)
                .font(.caption)
                .foregroundStyle(model.showsValue ? .secondary : model.theme.variable.unresolved)

            if model.showsValue {
                TextField("Value", text: $model.draft)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.draft) { _, newValue in
                        onEdit(newValue)
                    }
            } else {
                Text("This variable has no value in the current environment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(model.environmentName == nil ? "Add to Collection Variables" : "Add to Current Environment") {
                    onAdd()
                }
            }
        }
        .padding(14)
        .frame(width: 264, alignment: .leading)
    }
}

private struct VariableSuggestionPopover: View {
    var model: VariableSuggestionPopoverModel
    var onPick: (VariableSuggestion) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.items) { item in
                    VariableSuggestionRow(
                        item: item,
                        isSelected: item.id == model.selectedID,
                        onHover: { model.selectedID = item.id },
                        onPick: { onPick(item) }
                    )
                }
            }
        }
        .frame(width: 300)
        .padding(.vertical, 4)
    }
}

private struct VariableSuggestionRow: View {
    let item: VariableSuggestion
    var isSelected: Bool
    var onHover: () -> Void
    var onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack {
                Text(item.insertion)
                    .font(.body.monospaced())
                Spacer(minLength: 8)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { onHover() }
        }
        .accessibilityLabel(item.insertion)
        .accessibilityValue(detail)
    }

    private var detail: String {
        let value = item.value.isEmpty ? "empty" : item.value
        return "\(item.origin.title) · \(value)"
    }
}

#Preview("Token") {
    let model = VariableTokenPopoverModel()
    model.token = VariableToken(
        name: "baseUrl",
        nsRange: NSRange(location: 0, length: 11),
        resolvedValue: "https://api.example.com",
        origin: .environment(name: "Local")
    )
    model.draft = "https://api.example.com"
    return VariableTokenPopover(model: model, onAdd: {}, onEdit: { _ in })
        .padding()
}

#Preview("Suggestions") {
    let model = VariableSuggestionPopoverModel()
    model.items = [
        VariableSuggestion(key: "baseUrl", value: "https://api.example.com", origin: .environment(name: "Local")),
        VariableSuggestion(key: "token", value: "", origin: .collection),
    ]
    model.selectedID = model.items.first?.id
    return VariableSuggestionPopover(model: model, onPick: { _ in })
}
