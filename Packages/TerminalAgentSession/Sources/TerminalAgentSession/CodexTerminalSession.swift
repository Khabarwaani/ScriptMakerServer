import Foundation
import Synchronization
import AgentAtom

/// An `AgentAtom.AgenticSessionProtocol` implementation driving Codex CLI (`codex`).
public final class CodexTerminalSession: TerminalSessionProtocol {
    public let configuration: Configuration
    private let state = Mutex(State())

    public var executionMetadata: [AgenticExecutionMetadata] {
        state.withLock { $0.records }
    }

    public typealias Configuration = TerminalAgentConfiguration

    public init?(configuration: Configuration = Configuration(executablePath: "codex")) {
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

        let admitted = state.withLock { state -> Bool in
            guard !state.isBusy else { return false }
            state.isBusy = true
            return true
        }
        guard admitted else { return .failure(.busy) }

        let startTime = ContinuousClock().now
        let executionID = UUID()

        defer {
            let record = AgenticExecutionMetadata(
                operationID: operation,
                executionID: executionID,
                modelIdentifier: configuration.metadata.contains(.modelIdentifier) ? (configuration.model ?? "codex") : nil,
                duration: configuration.metadata.contains(.duration) ? startTime.duration(to: ContinuousClock().now) : nil,
                promptTokens: nil,
                completionTokens: nil
            )
            state.withLock { state in
                state.records.append(record)
                state.isBusy = false
            }
        }

        guard let executableURL = configuration.resolvedURL else {
            return .failure(.operationFailed(reason: "Codex CLI executable not found at '\(configuration.executablePath)'"))
        }

        // Prepare temporary files for schema and output
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("codex_\(executionID.uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return .failure(.operationFailed(reason: "Failed to create temporary directory: \(error.localizedDescription)"))
        }
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let schemaFile = tempDir.appendingPathComponent("schema.json")
        let outputFile = tempDir.appendingPathComponent("output.json")

        let strictSchema: String
        do {
            strictSchema = try CodexStrictSchemaBridge.convertToCodexStrict(schemaJSON: schema.rawValue)
            try strictSchema.write(to: schemaFile, atomically: true, encoding: .utf8)
        } catch {
            return .failure(.operationFailed(reason: "Failed to write output schema: \(error.localizedDescription)"))
        }

        var arguments: [String] = ["exec"]
        if let model = configuration.model {
            arguments += ["--model", model]
        }
        arguments += [
            "--output-schema", schemaFile.path,
            "-o", outputFile.path
        ]
        arguments += configuration.extraArguments

        // Format combined prompt containing instructions and input
        let promptText = "\(instructions)\n\nInput:\n\(input)"
        arguments.append(promptText)

        do {
            let result: TerminalProcessRunner.ExecutionResult = try await TerminalProcessRunner.streamLines(
                executableURL: executableURL,
                arguments: arguments,
                currentDirectoryURL: configuration.workingDirectory,
                yield: yield
            )

            guard result.exitCode == 0 else {
                let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(.operationFailed(reason: "Codex CLI exited with status \(result.exitCode): \(err)"))
            }

            // Prefer result written directly to outputFile
            if FileManager.default.fileExists(atPath: outputFile.path),
               let outputData = try? Data(contentsOf: outputFile),
               let outputString = String(data: outputData, encoding: .utf8),
               !outputString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .success(outputString)
            }

            // Fallback to stdout
            let trimmedStdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedStdout.isEmpty {
                return .success(trimmedStdout)
            }

            return .failure(.generationFailed(reason: "Codex CLI produced no output."))
        } catch let error as AgenticError {
            return .failure(error)
        } catch {
            return .failure(.operationFailed(reason: error.localizedDescription))
        }
    }
}
