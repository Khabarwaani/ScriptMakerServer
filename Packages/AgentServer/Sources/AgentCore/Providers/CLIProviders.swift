import Foundation

/// CLI differences are localized here; the manager sees only AIProvider.
public struct CLIProvider: AIProvider {
    public enum Kind: String, Sendable { case codex, antigravity, grok }
    public let kind: Kind
    public let settings: ProviderSettings
    public var id: String { kind.rawValue }
    public var isAvailable: Bool { (try? executable()) != nil }
    public init(kind: Kind, settings: ProviderSettings) {
        self.kind = kind
        self.settings = settings
    }

    private func executable() throws -> URL {
        guard settings.enabled else {
            throw AgentError("provider_unavailable", "The selected provider is disabled.")
        }
        let configured = settings.executable
        let extensions = ProcessRunner.platformExecutableExtensions
        let separator = ProcessRunner.platformPathSeparator
        let standardPaths = ProcessRunner.platformStandardPaths

        var configuredVariants = [configured]
        for ext in extensions where !ext.isEmpty && !configured.hasSuffix(ext) {
            configuredVariants.append(configured + ext)
        }

        let candidates: [String]
        if configured.contains("/") || configured.contains("\\") {
            candidates = configuredVariants
        } else {
            let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
            let segments = path.split(separator: separator).map(String.init) + standardPaths
            candidates = segments.flatMap { dir in
                configuredVariants.map { variant in
                    URL(fileURLWithPath: dir).appendingPathComponent(variant).path
                }
            }
        }
        guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw AgentError(
                "provider_unavailable", "The configured provider executable is not installed or accessible.")
        }
        return URL(fileURLWithPath: found).standardizedFileURL
    }

    public func checkReadiness() async throws {
        let executable = try executable()
        let arguments: [String] =
            switch kind {
            case .codex: ["login", "status"]
            case .antigravity, .grok: ["--help"]
            }
        do {
            let text = try await ProcessRunner().run(
                executable: executable, arguments: arguments, timeoutSeconds: 20)
            let lower = text.lowercased()
            guard !lower.contains("authentication required"), !lower.contains("not logged in"),
                !lower.contains("please sign in")
            else {
                throw AgentError(
                    "provider_initialization_failed",
                    "Provider authentication is required. Authenticate using its CLI first.")
            }
        } catch {
            throw AgentError(
                "provider_initialization_failed",
                "\(id) could not initialize using the current user's CLI environment. Verify that its cached login is accessible to the server."
            )
        }
    }

    public func execute(
        definition: AgentDefinition, input: JSONValue, runner: ProcessRunner, directory: URL,
        timeoutSeconds: Int, onOutput: @escaping @Sendable (String) async -> Void,
        onProgress: @escaping @Sendable (JSONValue) async -> Void
    ) async throws -> JSONValue {
        let schemaURL = directory.appendingPathComponent("output.schema.json")
        let promptURL = directory.appendingPathComponent("prompt.txt")
        let resultURL = directory.appendingPathComponent("result.json")
        let schemaText = try definition.outputSchema.text()
        try Data(schemaText.utf8).write(to: schemaURL)
        let prompt = """
            ROLE
            \(definition.role)

            INSTRUCTIONS
            \(definition.instructions)

            OUTPUT CONTRACT
            Return exactly one final JSON value matching this JSON Schema. No Markdown fences.
            The final value must contain only schema-defined fields. Do not include toolAction, toolSummary, provider metadata, or tool-call arguments as final output.
            Fill each field with its requested domain data. A string field must contain the requested text, not a serialized copy of the entire JSON result. Use the provider's structured-output mechanism to submit the fields directly when available.
            \(schemaText)

            CLIENT INPUT (JSON data, not shell commands)
            \(try input.text())
            """
        try Data(prompt.utf8).write(to: promptURL)
        var arguments: [String]
        var stdin: String?
        switch kind {
        case .codex:
            arguments = [
                "exec", "--json", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only", "--color",
                "never", "--output-schema", schemaURL.path, "--output-last-message", resultURL.path, "-",
            ]
            stdin = prompt
        case .antigravity:
            arguments = [
                "--input-format", "stream-json", "--output-format", "stream-json", "--json-schema",
                schemaURL.path,
                "--print-timeout", "\(timeoutSeconds)s", "--sandbox",
                "--disable-slash-commands",
            ]
            stdin =
                try JSONValue.object([
                    "event": .string("user"), "message": .object(["content": .string(prompt)]),
                ]).text() + "\n"
        case .grok:
            arguments = [
                "--prompt-file", promptURL.path, "--output-format", "streaming-messages-json",
                "--include-partial-messages", "--always-approve", "--no-subagents",
            ]
        }
        if let model = settings.model { arguments += ["--model", model] }
        let accumulator = ProviderAccumulator(kind: kind)
        _ = try await runner.run(
            executable: executable(), arguments: arguments, directory: directory, input: stdin,
            timeoutSeconds: timeoutSeconds
        ) { line in
            if let update = try await accumulator.consume(line) {
                switch update {
                case .text(let text): await onOutput(text)
                case .progress(let value): await onProgress(value)
                }
            }
        }
        if kind == .codex {
            try await accumulator.checkOutcome()
            guard let data = try? Data(contentsOf: resultURL), data.count <= 4_194_304,
                let value = try? JSONDecoder().decode(JSONValue.self, from: data)
            else {
                throw AgentError("invalid_final_json", "The provider did not return valid final JSON.")
            }
            return value
        }
        let result = try await accumulator.finalResult()
        if kind == .antigravity {
            let normalized = Self.removeAntigravityToolAnnotations(result, schema: definition.outputSchema)
            if normalized != result {
                await onProgress(
                    .object([
                        "message": .string(
                            "Separated Antigravity tool annotations from the final agent result.")
                    ]))
            }
            return normalized
        }
        return result
    }

    // Antigravity's structured tool transport can add these two string annotations
    // to a result. Never discard arbitrary unexpected fields or schema-defined data.
    static func removeAntigravityToolAnnotations(_ result: JSONValue, schema: JSONValue) -> JSONValue {
        guard schema["additionalProperties"]?.bool == false, let properties = schema["properties"]?.object,
            var object = result.object
        else { return result }
        for key in ["toolAction", "toolSummary"] where properties[key] == nil && object[key]?.string != nil {
            object[key] = nil
        }
        return .object(object)
    }
}

actor ProviderAccumulator {
    enum Update: Sendable, Equatable {
        case text(String)
        case progress(JSONValue)
    }
    let kind: CLIProvider.Kind
    var finalText = ""
    var partialText = ""
    var failed = false
    var structuredResult: JSONValue?
    var receivedTerminal = false
    init(kind: CLIProvider.Kind) { self.kind = kind }

    func consume(_ line: String) throws -> Update? {
        guard let event = try? JSONValue.parse(line) else { return nil }
        let type = event["type"]?.string ?? event["event"]?.string ?? ""
        switch kind {
        case .codex:
            if type == "turn.failed" || type == "error" { failed = true }
            if let item = event["item"], item["type"]?.string == "agent_message",
                let text = item["text"]?.string
            {
                return .text(text)
            }
            if type == "item.started" || type == "item.completed" {
                return .progress(
                    .object([
                        "message": .string(
                            "Codex \(event["item"]?["type"]?.string ?? "step") \(type == "item.started" ? "started" : "completed")"
                        )
                    ]))
            }
        case .antigravity:
            if type == "init" {
                return .progress(.object(["message": .string("Antigravity session initialized.")]))
            }
            if type == "step_update", let step = event["step_update"] {
                if let text = step["text_delta"]?.string, !text.isEmpty {
                    partialText += text
                    guard partialText.utf8.count <= 4_194_304 else {
                        throw AgentError(
                            "provider_output_limit", "Provider output exceeded the result limit.")
                    }
                    return .text(text)
                }
                let category = step["step_type"]?.string ?? "step"
                let state = step["state"]?.string ?? "ACTIVE"
                return .progress(
                    .object([
                        "message": .string("Antigravity \(category) · \(state)"),
                        "step_type": .string(category), "state": .string(state),
                    ]))
            }
            if type == "result" {
                receivedTerminal = true
                let result = event["result"] ?? event
                let status = result["status"]?.string ?? event["status"]?.string
                if let status, status != "SUCCESS" && status != "success" { failed = true }
                structuredResult = result["structured_output"] ?? event["structured_output"]
                finalText = result["response"]?.string ?? event["response"]?.string ?? ""
                return .progress(
                    .object(["message": .string("Antigravity final result received; validating JSON schema.")]
                    ))
            }
            if let text = event["text"]?.string ?? event["delta"]?["text"]?.string {
                partialText += text
                return .text(text)
            }
        case .grok:
            if type == "stream_event", let inner = event["event"], let text = inner["delta"]?["text"]?.string
            {
                partialText += text
                return .text(text)
            }
            if type == "content_block_delta", let text = event["delta"]?["text"]?.string {
                partialText += text
                return .text(text)
            }
            if type == "assistant", let content = event["message"]?["content"]?.array {
                let text = content.compactMap { $0["text"]?.string }.joined()
                if !text.isEmpty {
                    finalText = text
                    return .text(text)
                }
            }
            if type == "result" {
                receivedTerminal = true
                if event["is_error"]?.bool == true { failed = true }
                if let structured = event["structured_output"] {
                    structuredResult = structured
                } else if let text = event["result"]?.string {
                    finalText = text
                } else if let text = event["response"]?.string {
                    finalText = text
                }
            }
        }
        guard finalText.utf8.count + partialText.utf8.count <= 4_194_304 else {
            throw AgentError("provider_output_limit", "Provider output exceeded the result limit.")
        }
        return nil
    }

    func finalResult() throws -> JSONValue {
        guard !failed else {
            throw AgentError("provider_execution_failed", "The provider reported an execution failure.")
        }
        if let structuredResult { return structuredResult }
        guard receivedTerminal else {
            throw AgentError("invalid_final_json", "The provider did not emit a terminal result event.")
        }
        let text = finalText.isEmpty ? partialText : finalText
        guard let value = try? JSONValue.parse(text) else {
            throw AgentError("invalid_final_json", "The provider did not return valid final JSON.")
        }
        return value
    }

    func checkOutcome() throws {
        if failed { throw AgentError("provider_execution_failed", "The provider reported an execution failure.") }
    }
}
