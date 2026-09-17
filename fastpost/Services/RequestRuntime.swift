import Foundation

@Observable
final class RequestRuntime {
    var states: [String: RequestRunState] = [:]
    var scriptResults: [String: PostResponseResult] = [:]

    @ObservationIgnored
    var certificates: ClientCertificateStore?

    @ObservationIgnored
    weak var automation: (any PostResponseAutomation)?

    @ObservationIgnored
    private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored
    private let clientOverride: HTTPClient?
    @ObservationIgnored
    private let identityCache = ClientIdentityCache()
    @ObservationIgnored
    private let cookieJar: HTTPCookieStorage

    init(client: HTTPClient? = nil) {
        self.clientOverride = client
        self.cookieJar = URLSessionConfiguration.ephemeral.httpCookieStorage ?? HTTPCookieStorage()
    }

    func state(for id: String?) -> RequestRunState {
        guard let id else { return .idle }
        return states[id] ?? .idle
    }

    func scriptResult(for id: String?) -> PostResponseResult? {
        guard let id else { return nil }
        return scriptResults[id]
    }

    var isSendingSelected: Bool {
        false
    }

    func isSending(_ id: String?) -> Bool {
        guard let id else { return false }
        return states[id] == .sending
    }

    func send(id: String, request: HTTPRequest) {
        cancel(id, markCancelled: false)
        states[id] = .sending
        scriptResults[id] = nil
        tasks[id] = Task {
            let client: HTTPClient
            if let clientOverride {
                client = clientOverride
            } else {
                switch await resolveClient(for: request) {
                case .success(let resolved):
                    client = resolved
                case .failure(let failure):
                    guard !Task.isCancelled else { return }
                    states[id] = .failed(failure)
                    tasks[id] = nil
                    return
                }
            }

            let result = await client.send(request)
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let outcome):
                await runPostResponse(id: id, outcome: outcome)
            case .failure(let failure):
                states[id] = .failed(failure)
            }
            tasks[id] = nil
        }
    }

    private func runPostResponse(id: String, outcome: HTTPSendOutcome) async {
        guard let automation, !Task.isCancelled else {
            states[id] = .received(outcome.exchange)
            return
        }

        let program = automation.program(forRequestID: id)
        guard !program.isEmpty else {
            states[id] = .received(outcome.exchange)
            return
        }

        let exchange = outcome.exchange
        let rawBody = outcome.rawBody
        let extracted = await Task.detached(priority: .userInitiated) {
            ResponseExtractorRunner.run(
                extractors: program.extractors,
                exchange: exchange,
                rawBody: rawBody,
                hasEnvironment: program.hasEnvironment
            )
        }.value

        var result = PostResponseResult(extractorResults: extracted.results)
        var mutations = extracted.mutations

        if !program.scripts.isEmpty {
            let environmentValues = program.environmentValues
            let collectionValues = program.collectionValues
            let hasEnvironment = program.hasEnvironment
            let scripts = program.scripts
            let scriptOutcome = await Task.detached(priority: .userInitiated) {
                PostmanScriptRunner.run(
                    scripts: scripts,
                    exchange: exchange,
                    rawBody: rawBody,
                    environmentValues: environmentValues,
                    collectionValues: collectionValues,
                    hasEnvironment: hasEnvironment
                )
            }.value
            result.tests = scriptOutcome.result.tests
            result.logs = scriptOutcome.result.logs
            result.errorMessage = scriptOutcome.result.errorMessage
            mutations.append(contentsOf: scriptOutcome.mutations)
        }

        guard !Task.isCancelled else { return }
        if !mutations.isEmpty {
            automation.apply(mutations: mutations)
        }
        scriptResults[id] = result
        states[id] = .received(outcome.exchange)
    }

    private func resolveClient(for request: HTTPRequest) async -> Result<HTTPClient, HTTPTransportFailure> {
        var client = HTTPClient(preferences: .current)
        if client.preferences.useCookieJar {
            client.cookieStorage = cookieJar
        }
        guard let certificates,
              let matched = certificates.match(rawURL: request.rawURL)
        else {
            return .success(client)
        }

        do {
            let material = try certificates.material(for: matched)
            client.clientCredential = try await identityCache.credential(for: matched, material: material)
            return .success(client)
        } catch let error as ClientIdentityError {
            return .failure(.clientCertificate(error.transportMessage))
        } catch {
            return .failure(.clientCertificate(error.localizedDescription))
        }
    }

    func cancel(_ id: String, markCancelled: Bool = true) {
        tasks[id]?.cancel()
        tasks[id] = nil
        if markCancelled, states[id] == .sending {
            states[id] = .failed(.cancelled)
        }
    }

    func toggleSend(id: String, request: HTTPRequest) {
        if isSending(id) {
            cancel(id)
        } else {
            send(id: id, request: request)
        }
    }
}

extension RequestRuntime {
    static var preview: RequestRuntime {
        let runtime = RequestRuntime()
        runtime.states["preview-ok"] = .received(
            HTTPExchange(
                statusCode: 200,
                statusText: HTTPStatusPhrase.phrase(for: 200),
                duration: .milliseconds(142),
                byteCount: 128,
                headers: [HTTPHeader(key: "Content-Type", value: "application/json")],
                cookies: [ResponseCookie(name: "session", value: "abc", domain: "example.com", path: "/", isSecure: true, isHTTPOnly: true)],
                body: .json("{\n  \"ok\" : true\n}"),
                requestURL: URL(string: "https://api.example.com/health")!,
                finalURL: URL(string: "https://api.example.com/health")!,
                isTruncated: false
            )
        )
        runtime.scriptResults["preview-ok"] = PostResponseResult(
            extractorResults: [
                ExtractorRunResult(id: "token", variableKey: "token", value: "abc", isSuccess: true, message: "Saved token")
            ],
            tests: [ScriptTestResult(id: "status", name: "Status is 200", passed: true, message: nil)],
            logs: [ScriptLogLine(id: "log", level: .log, text: "token saved")]
        )
        return runtime
    }
}
