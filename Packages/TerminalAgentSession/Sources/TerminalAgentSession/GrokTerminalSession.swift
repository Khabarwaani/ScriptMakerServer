import Foundation
import AgentAtom

/// An `AgentAtom.AgenticSessionProtocol` implementation driving Grok CLI (`grok`).
public final class GrokTerminalSession: TerminalSessionProtocol, @unchecked Sendable {
    public let configuration: Configuration
    private let state = UnfairLock()
    private var stateStorage = State()

    public var executionMetadata: [AgenticExecutionMetadata] {
        state.withLock { stateStorage.records }
    }

    public typealias Configuration = TerminalAgentConfiguration

    public init?(configuration: Configuration = Configuration(executablePath: "grok")) {
        guard let resolvedURL = TerminalProcessRunner.resolveExecutable(named: configuration.executablePath) else {
            return nil
        }
        var updatedConfig = configuration
        updatedConfig.resolvedURL = resolvedURL
        self.configuration = updatedConfig
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

    private struct State: Sendable {
        var isBusy = false
        var records: [AgenticExecutionMetadata] = []
    }

    private func runSession(
        input: String,
        instructions: String,
        schema: JSONString,
        for operation: ObjectIdentifier,
        yield: (String) async -> Void
    ) async -> Result<String, AgenticError> {
        guard !Task.isCancelled else { return .failure(.cancelled) }

        let admitted = state.withLock {
            guard !stateStorage.isBusy else { return false }
            stateStorage.isBusy = true
            return true
        }
        guard admitted else { return .failure(.busy) }

        let startTime = ContinuousClock().now
        let executionID = UUID()

        defer {
            let record = AgenticExecutionMetadata(
                operationID: operation,
                executionID: executionID,
                modelIdentifier: configuration.metadata.contains(.modelIdentifier) ? (configuration.model ?? "grok") : nil,
                duration: configuration.metadata.contains(.duration) ? startTime.duration(to: ContinuousClock().now) : nil,
                promptTokens: nil,
                completionTokens: nil
            )
            state.withLock {
                stateStorage.records.append(record)
                stateStorage.isBusy = false
            }
        }

        guard let executableURL = configuration.resolvedURL else {
            return .failure(.operationFailed(reason: "Grok CLI executable not found at '\(configuration.executablePath)'"))
        }

        var arguments: [String] = [
            "--output-format", "streaming-messages-json",
            "--schema", schema.rawValue
        ]
        if let model = configuration.model {
            arguments += ["--model", model]
        }
        arguments += configuration.extraArguments

        let promptText = "\(instructions)\n\nInput:\n\(input)"
        arguments.append(promptText)

        do {
            var finalStructuredOutput = ""

            let result: TerminalProcessRunner.ExecutionResult
            result = try await TerminalProcessRunner.streamLines(
                executableURL: executableURL,
                arguments: arguments,
                currentDirectoryURL: configuration.workingDirectory,
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
