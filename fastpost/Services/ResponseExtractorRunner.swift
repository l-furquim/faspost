import Foundation

nonisolated enum ResponseExtractorRunner {
    static func run(
        extractors: [ResponseExtractor],
        exchange: HTTPExchange,
        rawBody: Data,
        hasEnvironment: Bool
    ) -> (results: [ExtractorRunResult], mutations: [VariableMutation]) {
        var results: [ExtractorRunResult] = []
        var mutations: [VariableMutation] = []
        let jsonObject = jsonObject(from: rawBody)

        for extractor in extractors where extractor.isEnabled {
            let key = extractor.variableKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }

            let extracted = value(
                for: extractor,
                exchange: exchange,
                jsonObject: jsonObject
            )
            if let extracted {
                results.append(
                    ExtractorRunResult(
                        id: extractor.id,
                        variableKey: key,
                        value: extracted,
                        isSuccess: true,
                        message: "Saved \(key)"
                    )
                )
                mutations.append(mutation(destination: extractor.destination, key: key, value: extracted, hasEnvironment: hasEnvironment))
            } else {
                results.append(
                    ExtractorRunResult(
                        id: extractor.id,
                        variableKey: key,
                        value: nil,
                        isSuccess: false,
                        message: missingValueMessage(for: extractor)
                    )
                )
            }
        }

        return (results, mutations)
    }

    static func value(
        in json: Any,
        path: String
    ) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return stringify(json)
        }

        var current: Any = json
        for segment in trimmed.split(separator: ".").map(String.init) {
            if let index = Int(segment), String(index) == segment, let array = current as? [Any], array.indices.contains(index) {
                current = array[index]
            } else if let object = current as? [String: Any], let next = object[segment] {
                current = next
            } else {
                return nil
            }
        }
        return stringify(current)
    }

    private static func value(
        for extractor: ResponseExtractor,
        exchange: HTTPExchange,
        jsonObject: Any?
    ) -> String? {
        switch extractor.source {
        case .json:
            guard let jsonObject else { return nil }
            return value(in: jsonObject, path: extractor.path)
        case .header:
            let name = extractor.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return exchange.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        case .cookie:
            let name = extractor.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return exchange.cookies.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        case .status:
            return String(exchange.statusCode)
        }
    }

    private static func mutation(
        destination: ResponseExtractorDestination,
        key: String,
        value: String,
        hasEnvironment: Bool
    ) -> VariableMutation {
        switch destination {
        case .environment:
            if hasEnvironment {
                return .setEnvironment(key: key, value: value)
            }
            return .setCollection(key: key, value: value)
        case .collection:
            return .setCollection(key: key, value: value)
        }
    }

    private static func missingValueMessage(for extractor: ResponseExtractor) -> String {
        switch extractor.source {
        case .json:
            return "No value at \(extractor.path.isEmpty ? "JSON body" : extractor.path)"
        case .header:
            return "Header “\(extractor.path)” was not found"
        case .cookie:
            return "Cookie “\(extractor.path)” was not found"
        case .status:
            return "Status was unavailable"
        }
    }

    private static func jsonObject(from data: Data) -> Any? {
        guard !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func stringify(_ value: Any) -> String? {
        if value is NSNull { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes]),
           let text = String(data: data, encoding: .utf8)
        {
            return text
        }
        return "\(value)"
    }
}
