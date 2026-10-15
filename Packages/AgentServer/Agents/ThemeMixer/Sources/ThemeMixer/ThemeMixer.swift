import Foundation

/// Provider-independent, versioned visual-theme instructions.
public enum ThemeMixerDefinition: Sendable {
    public static let id = "ThemeMixer"
    public static let versions: [String] = ["1.0.0", "1.1.0"]

    public static func directory(version: String) throws -> URL {
        guard versions.contains(version),
              let url = Bundle.module.url(forResource: version, withExtension: nil) else {
            throw DefinitionError.unknownVersion
        }
        return url
    }

    public static func role(version: String) throws -> String {
        let dir = try directory(version: version)
        return try String(contentsOf: dir.appendingPathComponent("role.md"), encoding: .utf8)
    }

    public static func instructions(version: String) throws -> String {
        let dir = try directory(version: version)
        return try String(contentsOf: dir.appendingPathComponent("instructions.md"), encoding: .utf8)
    }

    public static func outputSchema(version: String) throws -> String {
        let dir = try directory(version: version)
        return try String(contentsOf: dir.appendingPathComponent("output.schema.json"), encoding: .utf8)
    }

    public static func inputSchema(version: String) throws -> String? {
        let dir = try directory(version: version)
        return try String(contentsOf: dir.appendingPathComponent("input.schema.json"), encoding: .utf8)
    }

    public enum DefinitionError: Error {
        case unknownVersion
    }
}
