import Foundation

/// Provider-independent versioned instructions usable by another Swift package.
public enum ScriptWriterDefinition {
    public static let id = "ScriptWriter"
    public static var versions: [String] {
        guard let root = Bundle.module.resourceURL,
              let directories = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return directories.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("role.md").path) }.map(\.lastPathComponent).sorted()
    }

    public static func directory(version: String) throws -> URL {
        guard versions.contains(version),
              let url = Bundle.module.url(forResource: version, withExtension: nil) else {
            throw DefinitionError.unknownVersion
        }
        return url
    }

    public enum DefinitionError: Error { case unknownVersion }
}
