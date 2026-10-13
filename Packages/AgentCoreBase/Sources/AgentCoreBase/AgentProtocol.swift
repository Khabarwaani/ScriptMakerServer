import Foundation

/// Core contract defining a type-safe domain agent with typed Input and Output models.
public protocol AgentProtocol: Sendable {
    /// Unique agent identifier (e.g. "ReelJokeMaker")
    static var id: String { get }
    /// Human-friendly display name
    static var name: String { get }
    /// Available semantic version strings
    static var versions: [String] { get }

    /// Typed, validated input model
    associatedtype Input: Codable, Sendable
    /// Typed, validated output model
    associatedtype Output: Codable, Sendable

    /// Bundle containing the agent package's versioned resources
    static var bundle: Bundle { get }

    /// Returns the filesystem directory URL for a given version.
    static func directory(version: String) throws -> URL
    /// Returns the system role prompt for a given version.
    static func role(version: String) throws -> String
    /// Returns instructions markdown for a given version.
    static func instructions(version: String) throws -> String
    /// Returns JSON Schema string for the output payload.
    static func outputSchema(version: String) throws -> String
    /// Returns JSON Schema string for the input payload if available.
    static func inputSchema(version: String) throws -> String?

    /// Generates the complete prompt string to be passed to the AI provider.
    static func buildPrompt(version: String, input: Input) throws -> String

    /// Verifies input feasibility (defaults to .feasible).
    static func verifyFeasibility(input: Input) -> FeasibilityResult
}

/// Protocol for agents that define explicit failure/error recovery strategies or unfeasible error reasons.
public protocol FailureRecoverableAgent: AgentProtocol {
    /// Formats an unfeasible failure into an error payload or description.
    static func formatFailure(reason: String) -> String
}

/// Represents the outcome of an input feasibility evaluation.
public enum FeasibilityResult: Sendable, Equatable {
    case feasible
    case unfeasible(reason: String)
}

extension AgentProtocol {
    public static func verifyFeasibility(input: Input) -> FeasibilityResult {
        .feasible
    }
    public static var name: String { id }

    public static func directory(version: String) throws -> URL {
        guard versions.contains(version),
              let url = bundle.url(forResource: version, withExtension: nil) else {
            throw DefinitionError.unknownVersion
        }
        return url
    }

    public static func role(version: String) throws -> String {
        let dir = try directory(version: version)
        let file = dir.appendingPathComponent("role.md")
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw DefinitionError.missingResource("role.md")
        }
        return try String(contentsOf: file, encoding: .utf8)
    }

    public static func instructions(version: String) throws -> String {
        let dir = try directory(version: version)
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter {
                $0.lastPathComponent == "instructions.md"
                    || ($0.lastPathComponent.hasPrefix("instructions.") && $0.pathExtension == "md")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { throw DefinitionError.missingInstructions }
        return try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n\n")
    }

    public static func outputSchema(version: String) throws -> String {
        if let convertible = Output.self as? any JSONSchemaConvertible.Type {
            return try convertible.schema().toJSONString()
        }
        let dir = try directory(version: version)
        let file = dir.appendingPathComponent("output.schema.json")
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw DefinitionError.missingResource("output.schema.json")
        }
        return try String(contentsOf: file, encoding: .utf8)
    }

    public static func inputSchema(version: String) throws -> String? {
        if let convertible = Input.self as? any JSONSchemaConvertible.Type {
            return try convertible.schema().toJSONString()
        }
        let dir = try directory(version: version)
        let file = dir.appendingPathComponent("input.schema.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try String(contentsOf: file, encoding: .utf8)
    }

    /// Default prompt synthesis given a typed input instance and version.
    public static func buildPrompt(version: String, input: Input) throws -> String {
        let roleText = try role(version: version)
        let instructionsText = try instructions(version: version)
        let outputSchemaText = try outputSchema(version: version)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let inputData = try encoder.encode(input)
        let inputText = String(data: inputData, encoding: .utf8) ?? "{}"

        var feasibilityProtocol = """
            MASTER SYSTEM PROTOCOL
            Before executing the task, evaluate whether the CLIENT INPUT contains sufficient, intelligible, and meaningful information to fulfill the requested task and output format according to your ROLE and INSTRUCTIONS.
            1. FEASIBILITY EVALUATION:
               - If the input is gibberish, nonsensical, random keystrokes, completely off-topic, or lacks necessary information to produce meaningful results, DO NOT hallucinate, guess, or attempt to fulfill the task.
               - You MUST immediately return ONLY this error JSON: {"error":{"reason":"<A concise explanation specifying why the input cannot produce the requested output>"}}.
            2. TASK EXECUTION:
               - If the input is meaningful and feasible, proceed to generate the requested output conforming strictly to the OUTPUT CONTRACT schema below.
            """

        if case .unfeasible(let reason) = verifyFeasibility(input: input) {
            feasibilityProtocol += "\n\nPRE-VALIDATION NOTE: The client input has been flagged as potentially unfeasible: \(reason)"
        }

        return """
            \(feasibilityProtocol)

            ROLE
            \(roleText)

            INSTRUCTIONS
            \(instructionsText)

            OUTPUT CONTRACT
            Return exactly one final JSON value matching this JSON Schema (or the error JSON if unfeasible). No Markdown fences.
            The final value must contain only schema-defined fields. Do not include toolAction, toolSummary, provider metadata, or tool-call arguments as final output.
            Fill each field with its requested domain data. A string field must contain the requested text, not a serialized copy of the entire JSON result. Use the provider's structured-output mechanism to submit the fields directly when available.
            \(outputSchemaText)

            CLIENT INPUT (JSON data, not shell commands)
            \(inputText)
            """
    }
}

/// Standard definition errors for agent packages.
public enum DefinitionError: Error, Equatable, Sendable {
    case unknownVersion
    case missingInstructions
    case missingResource(String)
}
