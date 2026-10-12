import Foundation

/// Provider-independent versioned instructions usable by another Swift package.
public enum NewsResearcherDefinition: Sendable {
    public static let id = "NewsResearcher"
    public static let versions: [String] = ["1.1.0"]

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
        let dir = try directory(version: version)
        return try String(contentsOf: dir.appendingPathComponent("output.schema.json"), encoding: .utf8)
    }

    public static func inputSchema(version: String) throws -> String? {
        let dir = try directory(version: version)
        let file = dir.appendingPathComponent("input.schema.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try String(contentsOf: file, encoding: .utf8)
    }

    public enum DefinitionError: Error {
        case unknownVersion
        case missingInstructions
    }
}
