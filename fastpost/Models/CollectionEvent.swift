import Foundation

struct CollectionEvent: Codable, Equatable, Hashable, Sendable {
    var id: String?
    var listen: String
    var disabled: Bool?
    var script: PostmanScript

    static let extractorsScriptName = "Fastpost Extractors"
    static let testListen = "test"
    static let prerequestListen = "prerequest"

    var isTest: Bool { listen == Self.testListen }
    var isDisabled: Bool { disabled == true }
    var isFastpostExtractors: Bool { script.name == Self.extractorsScriptName }

    init(
        id: String? = nil,
        listen: String,
        disabled: Bool? = nil,
        script: PostmanScript
    ) {
        self.id = id
        self.listen = listen
        self.disabled = disabled
        self.script = script
    }

    static func test(source: String, name: String? = nil) -> CollectionEvent {
        CollectionEvent(listen: testListen, script: PostmanScript(name: name, source: source))
    }

    var runnableSource: String? {
        guard isTest, !isDisabled else { return nil }
        let source = script.source
        return source.isEmpty ? nil : source
    }

    static func splitExtractors(from events: [CollectionEvent]) -> (events: [CollectionEvent], extractors: [ResponseExtractor]) {
        var remaining: [CollectionEvent] = []
        var extractors: [ResponseExtractor] = []
        for event in events {
            if let parsed = FastpostExtractorCodec.parse(event) {
                extractors.append(contentsOf: parsed)
            } else {
                remaining.append(event)
            }
        }
        return (remaining, extractors)
    }

    static func merging(events: [CollectionEvent], extractors: [ResponseExtractor]) -> [CollectionEvent] {
        var merged = events.filter { !$0.isFastpostExtractors }
        if let generated = FastpostExtractorCodec.makeEvent(from: extractors) {
            merged.insert(generated, at: 0)
        }
        return merged
    }
}

struct PostmanScript: Codable, Equatable, Hashable, Sendable {
    var id: String?
    var type: String?
    var name: String?
    var exec: [String]

    var source: String {
        exec.joined(separator: "\n")
    }

    init(id: String? = nil, type: String? = "text/javascript", name: String? = nil, source: String) {
        self.id = id
        self.type = type
        self.name = name
        self.exec = Self.lines(from: source)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        name = JSONFlexible.string(from: container, forKey: .name)
        if let lines = try? container.decode([String].self, forKey: .exec) {
            exec = lines
        } else if let source = JSONFlexible.string(from: container, forKey: .exec) {
            exec = Self.lines(from: source)
        } else {
            exec = []
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case name
        case exec
    }

    private static func lines(from source: String) -> [String] {
        if source.isEmpty { return [] }
        return source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}

struct ResponseExtractor: Identifiable, Equatable, Hashable, Codable, Sendable {
    var id: String
    var isEnabled: Bool
    var source: ResponseExtractorSource
    var path: String
    var destination: ResponseExtractorDestination
    var variableKey: String

    init(
        id: String = UUID().uuidString,
        isEnabled: Bool = true,
        source: ResponseExtractorSource = .json,
        path: String = "",
        destination: ResponseExtractorDestination = .environment,
        variableKey: String = ""
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.source = source
        self.path = path
        self.destination = destination
        self.variableKey = variableKey
    }

    var hasContent: Bool {
        !variableKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum ResponseExtractorSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case json
    case header
    case cookie
    case status

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .json: "JSON"
        case .header: "Header"
        case .cookie: "Cookie"
        case .status: "Status"
        }
    }

    var pathPlaceholder: String {
        switch self {
        case .json: "data.access_token"
        case .header: "Authorization"
        case .cookie: "session"
        case .status: ""
        }
    }
}

enum ResponseExtractorDestination: String, Codable, CaseIterable, Identifiable, Sendable {
    case environment
    case collection

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .environment: "Environment"
        case .collection: "Collection"
        }
    }
}

enum FastpostExtractorCodec {
    static let marker = "// @fastpost-extractors "

    static func makeEvent(from extractors: [ResponseExtractor]) -> CollectionEvent? {
        let stored = extractors.filter(\.hasContent)
        guard !stored.isEmpty else { return nil }
        let payload = (try? JSONEncoder().encode(stored)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        var lines = [marker + payload]
        for extractor in stored where extractor.isEnabled {
            lines.append(generatedLine(for: extractor))
        }
        return CollectionEvent.test(source: lines.joined(separator: "\n"), name: CollectionEvent.extractorsScriptName)
    }

    static func parse(_ event: CollectionEvent) -> [ResponseExtractor]? {
        guard event.isFastpostExtractors else { return nil }
        let source = event.script.source
        if let markerLine = source.split(separator: "\n", omittingEmptySubsequences: false).first,
           markerLine.hasPrefix(marker)
        {
            let json = markerLine.dropFirst(marker.count)
            if let data = json.data(using: .utf8),
               let extractors = try? JSONDecoder().decode([ResponseExtractor].self, from: data)
            {
                return extractors
            }
        }
        return parseGeneratedJavaScript(source)
    }

    private static func generatedLine(for extractor: ResponseExtractor) -> String {
        let target = extractor.destination == .environment ? "pm.environment" : "pm.collectionVariables"
        let key = jsStringLiteral(extractor.variableKey)
        let value = jsExpression(for: extractor.source, path: extractor.path)
        return "\(target).set(\(key), \(value));"
    }

    static func jsExpression(for source: ResponseExtractorSource, path: String) -> String {
        switch source {
        case .json:
            return jsonAccess(path)
        case .header:
            return "pm.response.headers.get(\(jsStringLiteral(path)))"
        case .cookie:
            return "pm.cookies.get(\(jsStringLiteral(path)))"
        case .status:
            return "String(pm.response.code)"
        }
    }

    static func jsonAccess(_ path: String) -> String {
        var expression = "pm.response.json()"
        for part in path.split(separator: ".").map(String.init) where !part.isEmpty {
            if let index = Int(part), String(index) == part {
                expression += "[\(index)]"
            } else if part.range(of: "^[A-Za-z_$][A-Za-z0-9_$]*$", options: .regularExpression) != nil {
                expression += ".\(part)"
            } else {
                expression += "[\(jsStringLiteral(part))]"
            }
        }
        return expression
    }

    static func jsStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private static func parseGeneratedJavaScript(_ source: String) -> [ResponseExtractor] {
        source.split(separator: "\n").compactMap { line in
            parseGeneratedLine(String(line))
        }
    }

    private static func parseGeneratedLine(_ line: String) -> ResponseExtractor? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("pm.environment.set(") || trimmed.hasPrefix("pm.collectionVariables.set(") else {
            return nil
        }
        let destination: ResponseExtractorDestination = trimmed.hasPrefix("pm.environment") ? .environment : .collection
        guard let keyStart = trimmed.firstIndex(of: "\""),
              let keyEnd = trimmed[trimmed.index(after: keyStart)...].firstIndex(of: "\"")
        else { return nil }
        let key = String(trimmed[trimmed.index(after: keyStart)..<keyEnd])
        let afterKey = String(trimmed[trimmed.index(after: keyEnd)...])
        if afterKey.contains("pm.response.json()") {
            let path = jsonPath(fromJavaScript: afterKey)
            return ResponseExtractor(source: .json, path: path, destination: destination, variableKey: key)
        }
        if afterKey.contains("pm.response.headers.get(") {
            return ResponseExtractor(source: .header, path: firstQuoted(afterKey) ?? "", destination: destination, variableKey: key)
        }
        if afterKey.contains("pm.cookies.get(") {
            return ResponseExtractor(source: .cookie, path: firstQuoted(afterKey) ?? "", destination: destination, variableKey: key)
        }
        if afterKey.contains("pm.response.code") {
            return ResponseExtractor(source: .status, path: "", destination: destination, variableKey: key)
        }
        return nil
    }

    private static func jsonPath(fromJavaScript snippet: String) -> String {
        guard let jsonCall = snippet.range(of: "pm.response.json()") else { return "" }
        var remainder = snippet[jsonCall.upperBound...]
        var parts: [String] = []
        while remainder.hasPrefix(".") || remainder.hasPrefix("[") {
            if remainder.hasPrefix(".") {
                remainder = remainder.dropFirst()
                let name = remainder.prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }
                if name.isEmpty { break }
                parts.append(String(name))
                remainder = remainder.dropFirst(name.count)
            } else if remainder.hasPrefix("[") {
                remainder = remainder.dropFirst()
                if remainder.hasPrefix("\"") {
                    remainder = remainder.dropFirst()
                    let name = remainder.prefix { $0 != "\"" }
                    parts.append(String(name))
                    remainder = remainder.dropFirst(name.count)
                    if remainder.hasPrefix("\"") { remainder = remainder.dropFirst() }
                    if remainder.hasPrefix("]") { remainder = remainder.dropFirst() }
                } else {
                    let digits = remainder.prefix { $0.isNumber }
                    parts.append(String(digits))
                    remainder = remainder.dropFirst(digits.count)
                    if remainder.hasPrefix("]") { remainder = remainder.dropFirst() }
                }
            }
        }
        return parts.joined(separator: ".")
    }

    private static func firstQuoted(_ text: String) -> String? {
        guard let start = text.firstIndex(of: "\"") else { return nil }
        let after = text.index(after: start)
        guard let end = text[after...].firstIndex(of: "\"") else { return nil }
        return String(text[after..<end])
    }
}

extension CollectionItem {
    var testScriptSources: [String] {
        event.compactMap(\.runnableSource)
    }

    var userTestScriptText: String {
        event
            .filter { $0.isTest && !$0.isFastpostExtractors }
            .map(\.script.source)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    mutating func setUserTestScript(_ text: String) {
        let preserved = event.filter { !$0.isTest }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            event = preserved
        } else {
            event = preserved + [CollectionEvent.test(source: text)]
        }
    }
}

extension Collection {
    var testScriptSources: [String] {
        event.compactMap(\.runnableSource)
    }
}
