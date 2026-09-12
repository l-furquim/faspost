import AppKit
import SwiftUI

struct VariableTextField: View {
    @Binding var text: String
    var placeholder: String
    var onSubmit: (() -> Void)?

    @Environment(AppSession.self) private var session
    @Environment(\.appTheme) private var theme
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit { onSubmit?() }
            .background {
                VariableFieldBridge(
                    text: $text,
                    isFocused: isFocused,
                    theme: theme,
                    resolver: session.variableResolver,
                    environmentName: session.activeEnvironment?.name,
                    onAddVariable: { session.addVariable(name: $0) },
                    onEditVariable: { name, value, origin in
                        session.setVariableValue(name, to: value, origin: origin)
                    }
                )
            }
    }
}

private struct VariableFieldBridge: NSViewRepresentable {
    @Binding var text: String
    var isFocused: Bool
    var theme: AppTheme
    var resolver: VariableResolver
    var environmentName: String?
    var onAddVariable: (String) -> Void
    var onEditVariable: (String, String, VariableOrigin?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.coordinator = context.coordinator
        context.coordinator.configure()
        return view
    }

    func updateNSView(_ view: BridgeView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = isFocused
        context.coordinator.theme = theme
        context.coordinator.resolver = resolver
        context.coordinator.environmentName = environmentName
        context.coordinator.onAddVariable = onAddVariable
        context.coordinator.onEditVariable = onEditVariable
        view.coordinator = context.coordinator
        context.coordinator.refresh(from: view)
    }

    static func dismantleNSView(_ view: BridgeView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class Coordinator: NSObject {
        var text: Binding<String>
        var isFocused = false
        var theme = AppTheme.default
        var resolver = VariableResolver.empty
        var environmentName: String?
        var onAddVariable: ((String) -> Void)?
        var onEditVariable: ((String, String, VariableOrigin?) -> Void)?

        private let popover = VariablePopoverController()
        private var replacementRange = NSRange(location: 0, length: 0)
        private var keyMonitor: Any?
        private var mouseMonitor: Any?
        private var hideTokenWork: DispatchWorkItem?
        private var openTokenWork: DispatchWorkItem?
        private weak var attachedField: NSTextField?
        private weak var bridgeView: BridgeView?

        init(text: Binding<String>) {
            self.text = text
            super.init()
            popover.onPickSuggestion = { [weak self] suggestion in
                self?.insert(suggestion)
            }
            popover.onAddToken = { [weak self] token in
                self?.onAddVariable?(token.name)
            }
            popover.onEditToken = { [weak self] token, value in
                let origin = token.origin ?? (self?.environmentName == nil
                    ? .collection
                    : .environment(name: self?.environmentName ?? "Environment"))
                self?.onEditVariable?(token.name, value, origin)
            }
        }

        func configure() {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKey(event) ?? event
            }
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
                self?.handleMouse(event)
                return event
            }
        }

        func teardown() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            if let mouseMonitor {
                NSEvent.removeMonitor(mouseMonitor)
                self.mouseMonitor = nil
            }
            hideTokenWork?.cancel()
            openTokenWork?.cancel()
            popover.hide()
        }

        func refresh(from view: BridgeView) {
            bridgeView = view
            attachField(from: view)
            applyHighlight()
            if isFocused {
                updateCompletions()
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isFocused, let view = self.bridgeView else { return }
                    self.attachField(from: view)
                    self.highlightIdleField()
                }
            }
        }

        private func attachField(from view: BridgeView) {
            guard let field = view.enclosingTextField() else { return }
            field.allowsEditingTextAttributes = true
            attachedField = field
        }

        private func applyHighlight() {
            if isFocused, fieldEditor() != nil {
                highlightEditor()
            } else {
                highlightIdleField()
            }
        }

        private func fieldEditor() -> NSTextView? {
            attachedField?.currentEditor() as? NSTextView
        }

        private func highlightEditor() {
            guard let editor = fieldEditor(), let storage = editor.textStorage else { return }
            let selected = editor.selectedRange()
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttributes(
                [
                    .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                    .foregroundColor: NSColor(theme.syntax.text),
                ],
                range: full
            )
            for token in resolver.tokens(in: editor.string) {
                guard NSMaxRange(token.nsRange) <= storage.length else { continue }
                storage.addAttributes(
                    [
                        .foregroundColor: NSColor(token.isResolved ? theme.variable.resolved : theme.variable.unresolved),
                        .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium),
                    ],
                    range: token.nsRange
                )
            }
            storage.endEditing()
            let maxLength = storage.length
            let location = min(selected.location, maxLength)
            let length = min(selected.length, maxLength - location)
            editor.setSelectedRange(NSRange(location: location, length: length))
            editor.typingAttributes = [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor(theme.syntax.text),
            ]
        }

        private func highlightIdleField() {
            guard let field = attachedField, field.currentEditor() == nil else { return }
            let highlighted = NSMutableAttributedString(
                string: field.stringValue,
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                    .foregroundColor: NSColor(theme.syntax.text),
                ]
            )
            for token in resolver.tokens(in: field.stringValue) {
                guard NSMaxRange(token.nsRange) <= highlighted.length else { continue }
                highlighted.addAttributes(
                    [
                        .foregroundColor: NSColor(token.isResolved ? theme.variable.resolved : theme.variable.unresolved),
                        .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium),
                    ],
                    range: token.nsRange
                )
            }
            if field.attributedStringValue != highlighted {
                field.attributedStringValue = highlighted
            }
        }

        private func updateCompletions() {
            guard isFocused, let editor = fieldEditor() else { return }
            let caret = editor.selectedRange().location
            guard let incomplete = resolver.incompleteVariable(in: editor.string, caret: caret) else {
                popover.hideSuggestions()
                return
            }
            replacementRange = incomplete.replacementRange
            let suggestions = resolver.suggestions(matching: incomplete.prefix)
            if suggestions.isEmpty {
                popover.hideSuggestions()
                return
            }
            var actual = NSRange()
            let caretRect = editor.firstRect(
                forCharacterRange: NSRange(location: caret, length: 0),
                actualRange: &actual
            )
            popover.showSuggestions(
                suggestions,
                relativeTo: attachedField ?? editor,
                caretScreen: caretRect == .zero ? nil : caretRect.origin
            )
        }

        private func presentToken(_ token: VariableToken, in field: NSTextField) {
            let screen: NSRect
            if let editor = field.currentEditor() as? NSTextView {
                var actual = NSRange()
                let rect = editor.firstRect(forCharacterRange: token.nsRange, actualRange: &actual)
                guard rect != .zero else { return }
                screen = rect
            } else if let rect = field.screenRect(for: token.nsRange) {
                screen = rect
            } else {
                return
            }
            openTokenWork?.cancel()
            hideTokenWork?.cancel()
            popover.showToken(token, relativeTo: field, screenRect: screen, environmentName: environmentName, theme: theme)
        }

        private func insert(_ suggestion: VariableSuggestion) {
            guard let editor = fieldEditor(),
                  NSMaxRange(replacementRange) <= (editor.string as NSString).length
            else { return }
            editor.insertText(suggestion.insertion, replacementRange: replacementRange)
            if text.wrappedValue != editor.string {
                text.wrappedValue = editor.string
            }
            popover.hide()
        }

        private func handleKey(_ event: NSEvent) -> NSEvent? {
            if popover.isShowingSuggestions {
                switch event.keyCode {
                case 125:
                    popover.moveSelection(by: 1)
                    return nil
                case 126:
                    popover.moveSelection(by: -1)
                    return nil
                case 36, 48:
                    popover.confirmSelection()
                    return nil
                case 53:
                    popover.hide()
                    return nil
                default:
                    return event
                }
            }
            if event.keyCode == 53, popover.isShown {
                popover.hide()
                return nil
            }
            return event
        }

        private func handleMouse(_ event: NSEvent) {
            guard let field = attachedField, field.window != nil else { return }
            if popover.isShowingSuggestions { return }

            let screen = NSEvent.mouseLocation
            if popover.contains(screenPoint: screen) || popover.isEditingTokenValue {
                hideTokenWork?.cancel()
                openTokenWork?.cancel()
                return
            }

            guard field.contains(screenPoint: screen) else {
                scheduleHideToken()
                return
            }

            let token = token(atScreen: screen, in: field)
            if let token {
                if popover.shownTokenID == token.id {
                    hideTokenWork?.cancel()
                    openTokenWork?.cancel()
                } else if event.type == .leftMouseDown || popover.shownTokenID != nil {
                    presentToken(token, in: field)
                } else {
                    scheduleOpenToken(token, in: field)
                }
                return
            }

            if event.type == .leftMouseDown {
                openTokenWork?.cancel()
                hideTokenWork?.cancel()
                popover.hideToken()
            } else {
                scheduleHideToken()
            }
        }

        private func token(atScreen screen: NSPoint, in field: NSTextField) -> VariableToken? {
            let string = (field.currentEditor() as? NSTextView)?.string ?? field.stringValue
            let tokens = resolver.tokens(in: string)
            guard !tokens.isEmpty, let fieldPoint = field.point(fromScreen: screen) else { return nil }

            var best: (VariableToken, CGFloat)?
            for token in tokens {
                guard let rect = tokenRect(for: token, in: field) else { continue }
                let padded = rect.insetBy(dx: -1, dy: -4)
                guard padded.contains(fieldPoint) else { continue }
                let distance = abs(rect.midX - fieldPoint.x)
                if best == nil || distance < best!.1 {
                    best = (token, distance)
                }
            }
            return best?.0
        }

        private func tokenRect(for token: VariableToken, in field: NSTextField) -> NSRect? {
            if let editor = field.currentEditor() as? NSTextView {
                var actual = NSRange()
                let screen = editor.firstRect(forCharacterRange: token.nsRange, actualRange: &actual)
                guard screen != .zero, let window = field.window else { return nil }
                return field.convert(window.convertFromScreen(screen), from: nil)
            }
            return field.localRect(for: token.nsRange)
        }

        private func scheduleOpenToken(_ token: VariableToken, in field: NSTextField) {
            if popover.shownTokenID == token.id { return }
            openTokenWork?.cancel()
            hideTokenWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let screen = NSEvent.mouseLocation
                guard let current = self.token(atScreen: screen, in: field), current.id == token.id else { return }
                self.presentToken(token, in: field)
            }
            openTokenWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
        }

        private func scheduleHideToken() {
            openTokenWork?.cancel()
            if popover.isEditingTokenValue || popover.containsMouse { return }
            hideTokenWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.popover.containsMouse, !self.popover.isEditingTokenValue else { return }
                self.popover.hideToken()
            }
            hideTokenWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
}

private final class BridgeView: NSView {
    var coordinator: VariableFieldBridge.Coordinator?

    override var intrinsicContentSize: NSSize {
        .zero
    }

    func enclosingTextField() -> NSTextField? {
        guard window != nil else { return nil }
        let probe = convert(bounds, to: nil)
        let center = NSPoint(x: probe.midX, y: probe.midY)
        var current: NSView? = superview
        var depth = 0
        while let view = current, depth < 8 {
            let fields = view.collectTextFields()
            if !fields.isEmpty {
                if let hit = fields.first(where: {
                    let rect = $0.convert($0.bounds, to: nil)
                    return rect.contains(center) || rect.intersects(probe)
                }) {
                    return hit
                }
                return fields.min { lhs, rhs in
                    let left = lhs.convert(lhs.bounds, to: nil)
                    let right = rhs.convert(rhs.bounds, to: nil)
                    return hypot(left.midX - center.x, left.midY - center.y)
                        < hypot(right.midX - center.x, right.midY - center.y)
                }
            }
            current = view.superview
            depth += 1
        }
        return nil
    }
}

private extension NSView {
    func collectTextFields() -> [NSTextField] {
        var fields: [NSTextField] = []
        if let field = self as? NSTextField {
            fields.append(field)
        }
        for subview in subviews {
            fields.append(contentsOf: subview.collectTextFields())
        }
        return fields
    }
}

private extension NSTextField {
    func contains(screenPoint: NSPoint) -> Bool {
        guard let point = point(fromScreen: screenPoint) else { return false }
        return bounds.insetBy(dx: -2, dy: -2).contains(point)
    }

    func point(fromScreen screen: NSPoint) -> NSPoint? {
        guard let window else { return nil }
        return convert(window.convertFromScreen(NSRect(origin: screen, size: .zero)).origin, from: nil)
    }

    func localRect(for range: NSRange) -> NSRect? {
        let titleRect = cell?.titleRect(forBounds: bounds) ?? bounds
        let storage = NSTextStorage(attributedString: attributedStringValue)
        let container = NSTextContainer(containerSize: titleRect.size)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        container.lineFragmentPadding = 2
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        return NSRect(
            x: titleRect.minX + rect.minX,
            y: titleRect.minY,
            width: max(rect.width, 8),
            height: bounds.height
        )
    }

    func screenRect(for range: NSRange) -> NSRect? {
        guard let window, let local = localRect(for: range) else { return nil }
        return window.convertToScreen(convert(local, to: nil))
    }
}
