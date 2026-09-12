import Foundation

struct VariableResolver: Equatable {
    var environmentValues: [Variable]
    var collectionValues: [Variable]
    var environmentName: String?

    static let empty = VariableResolver(environmentValues: [], collectionValues: [])

    func lookup(_ key: String) -> (value: String, origin: VariableOrigin)? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let match = environmentValues.first(where: { $0.isEnabled && $0.key == trimmed }) {
            return (match.value, .environment(name: environmentName ?? "Environment"))
        }
        if let match = collectionValues.first(where: { $0.isEnabled && $0.key == trimmed }) {
            return (match.value, .collection)
        }
        return nil
    }

    func resolve(_ text: String) -> String {
        var current = text
        for _ in 0..<8 {
            let expanded = expandOnce(current)
            if expanded == current { break }
            current = expanded
        }
        return current
    }

    func suggestions(matching prefix: String) -> [VariableSuggestion] {
        let needle = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var seen = Set<String>()
        var all: [VariableSuggestion] = []

        func append(_ variables: [Variable], origin: VariableOrigin) {
            for variable in variables where variable.isEnabled && !variable.key.isEmpty {
                guard seen.insert(variable.key).inserted else { continue }
                all.append(VariableSuggestion(key: variable.key, value: variable.value, origin: origin))
            }
        }

        if let environmentName {
            append(environmentValues, origin: .environment(name: environmentName))
        } else {
            append(environmentValues, origin: .environment(name: "Environment"))
        }
        append(collectionValues, origin: .collection)

        guard !needle.isEmpty else {
            return all.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        }

        let prefixed = all.filter { $0.key.lowercased().hasPrefix(needle) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        let contained = all.filter { !$0.key.lowercased().hasPrefix(needle) && $0.key.lowercased().contains(needle) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        return prefixed + contained
    }

    func incompleteVariable(in text: String, caret: Int) -> IncompleteVariable? {
        let nsText = text as NSString
        guard caret >= 0, caret <= nsText.length else { return nil }
        let before = nsText.substring(to: caret) as NSString
        let open = before.range(of: "{{", options: .backwards)
        guard open.location != NSNotFound else { return nil }
        let prefixStart = open.location + 2
        let prefixLength = caret - prefixStart
        guard prefixLength >= 0 else { return nil }
        let prefix = nsText.substring(with: NSRange(location: prefixStart, length: prefixLength))
        if prefix.contains("}") || prefix.contains("{") || prefix.contains("\n") {
            return nil
        }
        return IncompleteVariable(
            prefix: prefix,
            replacementRange: NSRange(location: open.location, length: caret - open.location)
        )
    }

    func tokens(in text: String) -> [VariableToken] {
        Self.tokenRegex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).compactMap { match in
            guard match.numberOfRanges > 1,
                  let nameRange = Range(match.range(at: 1), in: text)
            else { return nil }
            let name = String(text[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let found = lookup(name)
            return VariableToken(
                name: name,
                nsRange: match.range,
                resolvedValue: found?.value,
                origin: found?.origin
            )
        }
    }

    private func expandOnce(_ text: String) -> String {
        var output = text
        let nsText = text as NSString
        let matches = Self.tokenRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches.reversed() {
            guard match.numberOfRanges > 1,
                  let nameRange = Range(match.range(at: 1), in: text)
            else { continue }
            let name = String(text[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = lookup(name)?.value {
                output = (output as NSString).replacingCharacters(in: match.range, with: value)
            }
        }
        return output
    }

    private static let tokenRegex = try! NSRegularExpression(pattern: #"\{\{\s*([^{}]+?)\s*\}\}"#)
}

extension HTTPRequest {
    func resolved(using resolver: VariableResolver) -> HTTPRequest {
        var copy = self
        copy.url = .raw(resolver.resolve(rawURL))
        copy.header = header.map { header in
            HTTPHeader(
                key: resolver.resolve(header.key),
                value: resolver.resolve(header.value),
                disabled: header.disabled
            )
        }
        if var body {
            if let raw = body.raw {
                body.raw = resolver.resolve(raw)
            }
            if let form = body.urlencoded {
                body.urlencoded = form.map { field in
                    QueryParam(
                        key: resolver.resolve(field.key),
                        value: field.value.map { resolver.resolve($0) },
                        disabled: field.disabled
                    )
                }
            }
            copy.body = body
        }
        if var auth {
            auth.username = resolver.resolve(auth.username)
            auth.password = resolver.resolve(auth.password)
            auth.token = resolver.resolve(auth.token)
            auth.apiKeyName = resolver.resolve(auth.apiKeyName)
            auth.apiKeyValue = resolver.resolve(auth.apiKeyValue)
            copy.auth = auth
        }
        return copy
    }
}
