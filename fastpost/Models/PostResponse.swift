import Foundation

enum VariableMutation: Equatable, Sendable {
    case setEnvironment(key: String, value: String)
    case unsetEnvironment(key: String)
    case setCollection(key: String, value: String)
    case unsetCollection(key: String)
}

struct PostResponseProgram: Sendable {
    var extractors: [ResponseExtractor]
    var scripts: [String]
    var environmentValues: [String: String]
    var collectionValues: [String: String]
    var hasEnvironment: Bool

    var isEmpty: Bool {
        !extractors.contains(where: \.isEnabled) && scripts.isEmpty
    }
}

struct PostResponseResult: Equatable, Sendable {
    var extractorResults: [ExtractorRunResult] = []
    var tests: [ScriptTestResult] = []
    var logs: [ScriptLogLine] = []
    var errorMessage: String?

    var isEmpty: Bool {
        extractorResults.isEmpty && tests.isEmpty && logs.isEmpty && errorMessage == nil
    }
}

struct ExtractorRunResult: Identifiable, Equatable, Sendable {
    var id: String
    var variableKey: String
    var value: String?
    var isSuccess: Bool
    var message: String
}

struct ScriptTestResult: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var passed: Bool
    var message: String?
}

struct ScriptLogLine: Identifiable, Equatable, Sendable {
    var id: String
    var level: Level
    var text: String

    enum Level: String, Equatable, Sendable {
        case log
        case warn
        case error
    }
}

@MainActor
protocol PostResponseAutomation: AnyObject {
    func program(forRequestID id: String) -> PostResponseProgram
    func apply(mutations: [VariableMutation])
}
