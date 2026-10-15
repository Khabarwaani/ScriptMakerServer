import Foundation
import AgentAtom

/// An `AgentAtom.AgenticSessionProtocol` implementation driving Grok CLI (`grok`).
public final class GrokTerminalSession: TerminalSessionProtocol {
    public var configuration: TerminalAgentConfiguration { engine.configuration }
    public var executionMetadata: [AgenticExecutionMetadata] { engine.executionMetadata }

    public typealias Configuration = TerminalAgentConfiguration
    private let engine: TerminalSessionEngine

    public init?(configuration: Configuration = Configuration(executablePath: "grok")) {
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
            "--output-format", "streaming-messages-json",
            "--schema", schema.rawValue
        ]
        if let model = configuration.model {
            arguments += ["--model", model]
        }
        arguments += configuration.extraArguments
        let prompt = "\(instructions)\n\nInput:\n\(input)"
        arguments.append(prompt)

        do {
            var finalStructuredOutput = ""

            let result = try await engine.execute(
                arguments: arguments,
                operation: operation,
                defaultModel: "grok",
                yield: { line in
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }

                    if let data = trimmed.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let delta = obj["delta"] as? String {
                            await yield(delta)
                        } else if let content = obj["content"] as? String {
                            await yield(content)
                        }
                        if let finalResult = obj["result"] as? String {
                            finalStructuredOutput = finalResult
                        } else if let finalObj = obj["result"] {
                            if let resData = try? JSONSerialization.data(withJSONObject: finalObj, options: [.sortedKeys]) {
                                finalStructuredOutput = String(decoding: resData, as: UTF8.self)
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
                return .failure(.operationFailed(reason: "Grok CLI exited with status \(result.exitCode): \(err)"))
            }

            if !finalStructuredOutput.isEmpty {
                return .success(finalStructuredOutput)
            }

            let trimmedStdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedStdout.isEmpty {
                return .success(trimmedStdout)
            }

            return .failure(.generationFailed(reason: "Grok CLI produced no output."))
        } catch let error as AgenticError {
            return .failure(error)
        } catch {
            return .failure(.operationFailed(reason: error.localizedDescription))
        }
    }
}
