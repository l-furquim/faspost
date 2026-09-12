import AppKit
import SwiftUI

enum CodeLanguage {
    case json
    case plain
}

enum JSONHighlighter {
    static func apply(
        to storage: NSTextStorage,
        theme: AppTheme,
        language: CodeLanguage,
        fontSize: CGFloat = NSFont.systemFontSize
    ) {
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.setAttributes(attributes(color: theme.syntax.text, bold: false, fontSize: fontSize), range: fullRange)
        guard language == .json else { return }

        for token in tokenize(storage.string) {
            guard NSMaxRange(token.range) <= storage.length else { continue }
            let color: Color
            let bold: Bool
            switch token.kind {
            case .key:
                color = theme.syntax.key
                bold = true
            case .string:
                color = theme.syntax.string
                bold = false
            case .number:
                color = theme.syntax.number
                bold = false
            case .keyword:
                color = theme.syntax.keyword
                bold = true
            case .punctuation:
                color = theme.syntax.punctuation
                bold = false
            }
            storage.addAttributes(attributes(color: color, bold: bold, fontSize: fontSize), range: token.range)
        }
    }

    private static func attributes(color: Color, bold: Bool, fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: bold ? .semibold : .regular)
        return [
            .font: font,
            .foregroundColor: NSColor(color),
        ]
    }

    private struct Token {
        var range: NSRange
        var kind: Kind
    }

    private enum Kind {
        case key, string, number, keyword, punctuation
    }

    private static func tokenize(_ text: String) -> [Token] {
        let utf16 = text.utf16
        var tokens: [Token] = []
        var index = text.startIndex

        func utf16Offset(of i: String.Index) -> Int {
            utf16.distance(from: utf16.startIndex, to: i.samePosition(in: utf16) ?? utf16.endIndex)
        }

        while index < text.endIndex {
            let character = text[index]
            if character.isWhitespace {
                index = text.index(after: index)
                continue
            }

            if character == "\"" {
                let start = index
                index = text.index(after: index)
                var escaped = false
                while index < text.endIndex {
                    let current = text[index]
                    if escaped {
                        escaped = false
                    } else if current == "\\" {
                        escaped = true
                    } else if current == "\"" {
                        index = text.index(after: index)
                        break
                    }
                    index = text.index(after: index)
                }
                let lookahead = text[index...].drop(while: \.isWhitespace)
                let kind: Kind = lookahead.first == ":" ? .key : .string
                let location = utf16Offset(of: start)
                let length = utf16Offset(of: index) - location
                tokens.append(Token(range: NSRange(location: location, length: length), kind: kind))
                continue
            }

            if character == "-" || character.isNumber {
                let start = index
                if character == "-" {
                    index = text.index(after: index)
                }
                while index < text.endIndex, text[index].isNumber || "eE.+-".contains(text[index]) {
                    index = text.index(after: index)
                }
                let location = utf16Offset(of: start)
                let length = utf16Offset(of: index) - location
                if length > 0 {
                    tokens.append(Token(range: NSRange(location: location, length: length), kind: .number))
                }
                continue
            }

            if text[index...].hasPrefix("true") || text[index...].hasPrefix("false") || text[index...].hasPrefix("null") {
                let keyword = text[index...].hasPrefix("false") ? "false" : (text[index...].hasPrefix("true") ? "true" : "null")
                let start = index
                index = text.index(start, offsetBy: keyword.count, limitedBy: text.endIndex) ?? text.endIndex
                let location = utf16Offset(of: start)
                let length = utf16Offset(of: index) - location
                tokens.append(Token(range: NSRange(location: location, length: length), kind: .keyword))
                continue
            }

            if "{}[],:".contains(character) {
                let start = index
                index = text.index(after: index)
                let location = utf16Offset(of: start)
                tokens.append(Token(range: NSRange(location: location, length: 1), kind: .punctuation))
                continue
            }

            index = text.index(after: index)
        }

        return tokens
    }
}
