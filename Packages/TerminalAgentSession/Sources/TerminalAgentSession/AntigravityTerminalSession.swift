import Foundation
import AgentAtom

/// An `AgentAtom.AgenticSessionProtocol` implementation driving Antigravity CLI (`agy`).
public final class AntigravityTerminalSession: TerminalSessionProtocol {
    public var configuration: TerminalAgentConfiguration { engine.configuration }
    public var executionMetadata: [AgenticExecutionMetadata] { engine.executionMetadata }

    public typealias Configuration = TerminalAgentConfiguration
    private let engine: TerminalSessionEngine

    public init?(configuration: Configuration = Configuration(executablePath: "agy")) {
        guard let engine = TerminalSessionEngine(configuration: configuration) else { return nil }
        self.engine = engine
    }

    public func clearMemory() {
        engine.clearMemory()
    }

    public func respond(
        to input: String,
        instructions: String,
        schema: JSONString,
        for operation: ObjectIdentifier
    ) async -> Result<String, AgenticError> {
        await runSession(input: input, instructions: instructions, schema: schema, for: operation, yield: { _ in })
    }

    public func stream(
        to input: String,
        instructions: String,
        schema: JSONString,
        for operation: ObjectIdentifier,
        yield: @Sendable (String) async -> Void
    ) async -> Result<String, AgenticError> {
        await runSession(input: input, instructions: instructions, schema: schema, for: operation, yield: yield)
    }

    private func runSession(
        input: String,
        instructions: String,
        schema: JSONString,
        for operation: ObjectIdentifier,
        yield: (String) async -> Void
    ) async -> Result<String, AgenticError> {
        var arguments: [String] = [
            "--output-format", "stream-json",
            "--json-schema", schema.rawValue,
            "--dangerously-skip-permissions"
        ]
        if let model = configuration.model {
            arguments += ["--model", model]
        }
        arguments += configuration.extraArguments
        arguments.append(engine.formatPrompt(input: input, instructions: instructions))

        do {
            var finalStructuredOutput = ""

            let result = try await engine.execute(
                arguments: arguments,
                operation: operation,
                defaultModel: "agy",
                yield: { line in
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }

                    if let data = trimmed.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let type = obj["type"] as? String {
                            if type == "text" || type == "delta", let content = obj["content"] as? String {
                                await yield(content)
                            } else if type == "result" || type == "completed" {
                                if let res = obj["response"] as? String {
                                    finalStructuredOutput = res
                                } else if let resObj = obj["response"] {
                                    if let resData = try? JSONSerialization.data(withJSONObject: resObj, options: [.sortedKeys]) {
                                        finalStructuredOutput = String(decoding: resData, as: UTF8.self)
                                    }
                                }
                            }
                        }
                    } else {
                        await yield(trimmed)
                        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
                            finalStructuredOutput = trimmed
                        }
                    }
                }
            )

            guard result.exitCode == 0 else {
                let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(.operationFailed(reason: "Antigravity CLI exited with status \(result.exitCode): \(err)"))
            }

            if !finalStructuredOutput.isEmpty {
                engine.recordTurn(input: input, output: finalStructuredOutput)
                return .success(finalStructuredOutput)
            }

            let trimmedStdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedStdout.isEmpty {
                engine.recordTurn(input: input, output: trimmedStdout)
                return .success(trimmedStdout)
            }

            return .failure(.generationFailed(reason: "Antigravity CLI produced no output."))
        } catch let error as AgenticError {
            return .failure(error)
        } catch {
            return .failure(.operationFailed(reason: error.localizedDescription))
        }
    }
}
