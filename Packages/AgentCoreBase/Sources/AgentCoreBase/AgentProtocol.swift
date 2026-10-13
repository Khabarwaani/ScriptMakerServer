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
}

extension AgentProtocol {
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
}

/// Standard definition errors for agent packages.
public enum DefinitionError: Error, Equatable, Sendable {
    case unknownVersion
    case missingInstructions
    case missingResource(String)
}
