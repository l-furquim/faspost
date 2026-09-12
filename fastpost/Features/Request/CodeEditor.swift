import AppKit
import SwiftUI

struct CodeEditor: View {
    @Binding var text: String
    var isEditable = true
    var language = CodeLanguage.json

    @Environment(AppSession.self) private var session: AppSession?
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppPreferenceStorage.editorFontSize) private var fontSize = EditorPreferences.default.fontSize
    @AppStorage(AppPreferenceStorage.editorIndentSpaces) private var indentSpaces = EditorPreferences.default.indentSpaces

    var body: some View {
        CodeEditorRepresentable(
            text: $text,
            isEditable: isEditable,
            language: language,
            theme: theme,
            colorScheme: colorScheme,
            resolver: session?.variableResolver ?? .empty,
            fontSize: fontSize,
            indentSpaces: indentSpaces
        )
        .clipShape(.rect(cornerRadius: 8))
    }
}

private struct CodeEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    var language: CodeLanguage
    var theme: AppTheme
    var colorScheme: ColorScheme
    var resolver: VariableResolver
    var fontSize: Double
    var indentSpaces: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.focusRingType = .none

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        context.coordinator.fontSize = fontSize
        context.coordinator.indentSpaces = indentSpaces
        context.coordinator.configure(textView)
        applyChrome(to: scrollView, textView: textView)
        applyContent(to: textView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.language = language
        context.coordinator.theme = theme
        context.coordinator.colorScheme = colorScheme
        context.coordinator.resolver = resolver
        context.coordinator.isEditable = isEditable
        context.coordinator.fontSize = fontSize
        context.coordinator.indentSpaces = indentSpaces

        guard let textView = scrollView.documentView as? NSTextView else { return }
        applyChrome(to: scrollView, textView: textView)
        textView.isEditable = isEditable
        textView.isSelectable = true
        if !isEditable {
            context.coordinator.hideCompletions()
        }

        if textView.string != text {
            applyContent(to: textView, coordinator: context.coordinator)
        } else if context.coordinator.needsRestyle {
            context.coordinator.highlight(textView)
        }
    }

    private func applyChrome(to scrollView: NSScrollView, textView: NSTextView) {
        let background = NSColor(theme.editorBackground)
        scrollView.backgroundColor = background
        textView.backgroundColor = background
        textView.insertionPointColor = NSColor(theme.syntax.text)
        textView.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor(theme.syntax.text),
        ]
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor,
        ]
    }

    private func applyContent(to textView: NSTextView, coordinator: Coordinator) {
        let selected = textView.selectedRange()
        textView.string = text
        coordinator.highlight(textView)
        let maxLength = (text as NSString).length
        let location = min(selected.location, maxLength)
        let length = min(selected.length, maxLength - location)
        textView.setSelectedRange(NSRange(location: location, length: length))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var language = CodeLanguage.json
        var theme = AppTheme.default
        var colorScheme = ColorScheme.light
        var resolver = VariableResolver.empty
        var isEditable = true
        var fontSize = EditorPreferences.default.fontSize
        var indentSpaces = EditorPreferences.default.indentSpaces
        private var lastTheme = AppTheme.default
        private var lastLanguage = CodeLanguage.json
        private var lastColorScheme = ColorScheme.light
        private var lastFontSize = EditorPreferences.default.fontSize
        private let completions = VariablePopoverController()
        private var replacementRange = NSRange(location: 0, length: 0)
        private weak var activeTextView: NSTextView?

        init(text: Binding<String>) {
            self.text = text
            super.init()
            completions.onPick = { [weak self] suggestion in
                self?.insert(suggestion)
            }
        }

        func hideCompletions() {
            completions.hide()
        }

        var needsRestyle: Bool {
            lastTheme != theme
                || lastLanguage != language
                || lastColorScheme != colorScheme
                || lastFontSize != fontSize
        }

        func configure(_ textView: NSTextView) {
            textView.delegate = self
            textView.allowsUndo = true
            textView.isRichText = true
            textView.importsGraphics = false
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isAutomaticLinkDetectionEnabled = false
            textView.isAutomaticDataDetectionEnabled = false
            textView.isAutomaticTextCompletionEnabled = false
            textView.smartInsertDeleteEnabled = false
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
            textView.usesFontPanel = false
            textView.usesRuler = false
            textView.drawsBackground = true
            textView.textContainerInset = NSSize(width: 8, height: 8)
            textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.lineFragmentPadding = 5
        }

        func highlight(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let selected = textView.selectedRange()
            storage.beginEditing()
            JSONHighlighter.apply(to: storage, theme: theme, language: language, fontSize: fontSize)
            storage.endEditing()
            let maxLength = storage.length
            let location = min(selected.location, maxLength)
            let length = min(selected.length, maxLength - location)
            textView.setSelectedRange(NSRange(location: location, length: length))
            lastTheme = theme
            lastLanguage = language
            lastColorScheme = colorScheme
            lastFontSize = fontSize
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            activeTextView = textView
            let raw = textView.string
            if text.wrappedValue != raw {
                text.wrappedValue = raw
            }
            highlight(textView)
            updateCompletions(for: textView)
        }

        func textDidEndEditing(_ notification: Notification) {
            if completions.containsMouse { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.completions.containsMouse else { return }
                self.completions.hide()
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            updateCompletions(for: textView)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if completions.isVisible {
                if commandSelector == #selector(NSResponder.moveDown(_:)) {
                    completions.moveSelection(by: 1)
                    return true
                }
                if commandSelector == #selector(NSResponder.moveUp(_:)) {
                    completions.moveSelection(by: -1)
                    return true
                }
                if commandSelector == #selector(NSResponder.insertNewline(_:))
                    || commandSelector == #selector(NSResponder.insertTab(_:)) {
                    completions.confirmSelection()
                    return true
                }
                if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                    completions.hide()
                    return true
                }
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                let indent = String(repeating: " ", count: max(indentSpaces, 1))
                textView.insertText(indent, replacementRange: textView.selectedRange())
                return true
            }
            return false
        }

        private func updateCompletions(for textView: NSTextView) {
            guard isEditable else {
                completions.hide()
                return
            }
            if textView.window?.firstResponder !== textView {
                return
            }
            let caret = textView.selectedRange().location
            guard let incomplete = resolver.incompleteVariable(in: textView.string, caret: caret) else {
                completions.hide()
                return
            }
            replacementRange = incomplete.replacementRange
            let suggestions = resolver.suggestions(matching: incomplete.prefix)
            if suggestions.isEmpty {
                completions.hide()
                return
            }
            let caretRect = textView.firstRect(
                forCharacterRange: NSRange(location: caret, length: 0),
                actualRange: nil
            )
            completions.show(
                suggestions,
                relativeTo: textView,
                caretScreen: caretRect == .zero ? nil : caretRect.origin
            )
        }

        private func insert(_ suggestion: VariableSuggestion) {
            guard let textView = activeTextView ?? NSApp.keyWindow?.firstResponder as? NSTextView,
                  NSMaxRange(replacementRange) <= (textView.string as NSString).length
            else { return }
            textView.insertText(suggestion.insertion, replacementRange: replacementRange)
            completions.hide()
        }
    }
}

#Preview {
    @Previewable @State var text = "{\n  \"ok\": true,\n  \"count\": 3\n}"
    CodeEditor(text: $text)
        .environment(AppSession.preview)
        .padding()
        .frame(width: 480, height: 220)
}
