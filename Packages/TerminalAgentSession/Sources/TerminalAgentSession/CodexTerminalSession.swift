import Foundation
import AgentAtom

/// An `AgentAtom.AgenticSessionProtocol` implementation driving Codex CLI (`codex`).
public final class CodexTerminalSession: TerminalSessionProtocol {
    public var configuration: TerminalAgentConfiguration { engine.configuration }
    public var executionMetadata: [AgenticExecutionMetadata] { engine.executionMetadata }

    public typealias Configuration = TerminalAgentConfiguration
    private let engine: TerminalSessionEngine

    public init?(configuration: Configuration = Configuration(executablePath: "codex")) {
        guard let engine = TerminalSessionEngine(configuration: configuration) else { return nil }
        self.engine = engine
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
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("codex_\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return .failure(.operationFailed(reason: "Failed to create temporary directory: \(error.localizedDescription)"))
        }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let schemaFile = tempDir.appendingPathComponent("schema.json")
        let outputFile = tempDir.appendingPathComponent("output.json")

        do {
            try schema.rawValue.write(to: schemaFile, atomically: true, encoding: .utf8)
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
        arguments.append("\(instructions)\n\nInput:\n\(input)")

        do {
            let result = try await engine.execute(
                arguments: arguments,
                operation: operation,
                defaultModel: "codex",
                yield: yield
            )

            guard result.exitCode == 0 else {
                let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(.operationFailed(reason: "Codex CLI exited with status \(result.exitCode): \(err)"))
            }

            if FileManager.default.fileExists(atPath: outputFile.path),
               let outputData = try? Data(contentsOf: outputFile),
               let outputString = String(data: outputData, encoding: .utf8),
               !outputString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .success(outputString)
            }

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
