import Foundation
import JavaScriptCore

nonisolated enum PostmanScriptRunner {
    static let timeout: Duration = .seconds(2)

    static func run(
        scripts: [String],
        exchange: HTTPExchange,
        rawBody: Data,
        environmentValues: [String: String],
        collectionValues: [String: String],
        hasEnvironment: Bool
    ) -> (result: PostResponseResult, mutations: [VariableMutation]) {
        let source = scripts.joined(separator: "\n")
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (PostResponseResult(), [])
        }

        let box = RunBox()
        let lock = NSLock()
        var finished = false
        var outcome: (PostResponseResult, [VariableMutation]) = (
            PostResponseResult(errorMessage: "Script timed out after 2 seconds."),
            []
        )

        let work = DispatchWorkItem {
            let evaluated = evaluate(
                source: source,
                exchange: exchange,
                rawBody: rawBody,
                environmentValues: environmentValues,
                collectionValues: collectionValues,
                hasEnvironment: hasEnvironment,
                box: box
            )
            lock.lock()
            if !finished {
                finished = true
                outcome = evaluated
            }
            lock.unlock()
        }

        DispatchQueue.global(qos: .userInitiated).async(execute: work)
        if work.wait(timeout: .now() + 2) == .timedOut {
            lock.lock()
            finished = true
            lock.unlock()
            box.cancel()
        }
        return outcome
    }

    private static func evaluate(
        source: String,
        exchange: HTTPExchange,
        rawBody: Data,
        environmentValues: [String: String],
        collectionValues: [String: String],
        hasEnvironment: Bool,
        box: RunBox
    ) -> (PostResponseResult, [VariableMutation]) {
        let context = JSContext()
        guard let context else {
            return (PostResponseResult(errorMessage: "JavaScript is unavailable."), [])
        }

        var environment = environmentValues
        var collection = collectionValues
        var mutations: [VariableMutation] = []
        var logs: [ScriptLogLine] = []
        var tests: [ScriptTestResult] = []
        var thrown: String?

        context.exceptionHandler = { _, exception in
            thrown = exception?.toString()
        }

        let envGet: @convention(block) (String) -> String? = { key in
            environment[key]
        }
        let envSet: @convention(block) (String, JSValue?) -> Void = { key, value in
            guard !box.isCancelled else { return }
            let string = stringify(value)
            environment[key] = string
            mutations.append(hasEnvironment ? .setEnvironment(key: key, value: string) : .setCollection(key: key, value: string))
        }
        let envUnset: @convention(block) (String) -> Void = { key in
            guard !box.isCancelled else { return }
            environment.removeValue(forKey: key)
            mutations.append(hasEnvironment ? .unsetEnvironment(key: key) : .unsetCollection(key: key))
        }
        let colGet: @convention(block) (String) -> String? = { key in
            collection[key]
        }
        let colSet: @convention(block) (String, JSValue?) -> Void = { key, value in
            guard !box.isCancelled else { return }
            let string = stringify(value)
            collection[key] = string
            mutations.append(.setCollection(key: key, value: string))
        }
        let colUnset: @convention(block) (String) -> Void = { key in
            guard !box.isCancelled else { return }
            collection.removeValue(forKey: key)
            mutations.append(.unsetCollection(key: key))
        }
        let varGet: @convention(block) (String) -> String? = { key in
            environment[key] ?? collection[key]
        }
        let headerGet: @convention(block) (String) -> String? = { name in
            exchange.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        let cookieGet: @convention(block) (String) -> String? = { name in
            exchange.cookies.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        let log: @convention(block) (String, String) -> Void = { level, text in
            guard !box.isCancelled else { return }
            logs.append(ScriptLogLine(id: UUID().uuidString, level: ScriptLogLine.Level(rawValue: level) ?? .log, text: text))
        }
        let testPass: @convention(block) (String) -> Void = { name in
            guard !box.isCancelled else { return }
            tests.append(ScriptTestResult(id: UUID().uuidString, name: name, passed: true, message: nil))
        }
        let testFail: @convention(block) (String, String) -> Void = { name, message in
            guard !box.isCancelled else { return }
            tests.append(ScriptTestResult(id: UUID().uuidString, name: name, passed: false, message: message))
        }

        context.setObject(envGet, forKeyedSubscript: "__fpEnvGet" as NSString)
        context.setObject(envSet, forKeyedSubscript: "__fpEnvSet" as NSString)
        context.setObject(envUnset, forKeyedSubscript: "__fpEnvUnset" as NSString)
        context.setObject(colGet, forKeyedSubscript: "__fpColGet" as NSString)
        context.setObject(colSet, forKeyedSubscript: "__fpColSet" as NSString)
        context.setObject(colUnset, forKeyedSubscript: "__fpColUnset" as NSString)
        context.setObject(varGet, forKeyedSubscript: "__fpVarGet" as NSString)
        context.setObject(headerGet, forKeyedSubscript: "__fpHeaderGet" as NSString)
        context.setObject(cookieGet, forKeyedSubscript: "__fpCookieGet" as NSString)
        context.setObject(log, forKeyedSubscript: "__fpLog" as NSString)
        context.setObject(testPass, forKeyedSubscript: "__fpTestPass" as NSString)
        context.setObject(testFail, forKeyedSubscript: "__fpTestFail" as NSString)
        context.setObject(exchange.statusCode as NSNumber, forKeyedSubscript: "__fpStatusCode" as NSString)
        context.setObject(exchange.statusText as NSString, forKeyedSubscript: "__fpStatusText" as NSString)
        context.setObject((String(data: rawBody, encoding: .utf8) ?? "") as NSString, forKeyedSubscript: "__fpBody" as NSString)

        context.evaluateScript(bootstrap)
        if let thrown {
            return (PostResponseResult(tests: tests, logs: logs, errorMessage: thrown), mutations)
        }

        context.evaluateScript(source)
        if box.isCancelled {
            return (PostResponseResult(errorMessage: "Script timed out after 2 seconds."), [])
        }

        return (PostResponseResult(tests: tests, logs: logs, errorMessage: thrown), mutations)
    }

    private static func stringify(_ value: JSValue?) -> String {
        guard let value, !value.isUndefined, !value.isNull else { return "" }
        if value.isString { return value.toString() ?? "" }
        if let context = value.context,
           let json = context.objectForKeyedSubscript("JSON"),
           let stringify = json.objectForKeyedSubscript("stringify")
        {
            let encoded = stringify.call(withArguments: [value])
            if let text = encoded?.toString(), text != "undefined" {
                return text
            }
        }
        return value.toString() ?? ""
    }

    private static let bootstrap = """
    function __fpStringifyArgs(args) {
      return Array.prototype.slice.call(args).map(function(value) {
        if (value === undefined) { return "undefined"; }
        if (value === null) { return "null"; }
        if (typeof value === "string") { return value; }
        try { return JSON.stringify(value); } catch (e) { return String(value); }
      }).join(" ");
    }

    var console = {
      log: function() { __fpLog("log", __fpStringifyArgs(arguments)); },
      warn: function() { __fpLog("warn", __fpStringifyArgs(arguments)); },
      error: function() { __fpLog("error", __fpStringifyArgs(arguments)); }
    };

    var pm = {
      variables: {
        get: function(key) { return __fpVarGet(String(key)); }
      },
      environment: {
        get: function(key) { return __fpEnvGet(String(key)); },
        set: function(key, value) { __fpEnvSet(String(key), value); },
        unset: function(key) { __fpEnvUnset(String(key)); }
      },
      collectionVariables: {
        get: function(key) { return __fpColGet(String(key)); },
        set: function(key, value) { __fpColSet(String(key), value); },
        unset: function(key) { __fpColUnset(String(key)); }
      },
      globals: {
        get: function(key) { return __fpColGet(String(key)); },
        set: function(key, value) {
          __fpLog("warn", "pm.globals maps to collection variables in Fastpost");
          __fpColSet(String(key), value);
        },
        unset: function(key) { __fpColUnset(String(key)); }
      },
      cookies: {
        get: function(name) { return __fpCookieGet(String(name)); }
      },
      response: {
        code: __fpStatusCode,
        status: __fpStatusText,
        json: function() { return JSON.parse(__fpBody || "null"); },
        text: function() { return __fpBody; },
        headers: {
          get: function(name) { return __fpHeaderGet(String(name)); }
        }
      },
      test: function(name, fn) {
        try {
          fn();
          __fpTestPass(String(name));
        } catch (error) {
          __fpTestFail(String(name), String(error));
        }
      }
    };
    """
}

private final class RunBox: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
