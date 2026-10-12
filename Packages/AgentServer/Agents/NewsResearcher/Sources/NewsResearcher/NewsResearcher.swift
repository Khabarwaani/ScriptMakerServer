import Foundation

/// Provider-independent versioned instructions usable by another Swift package.
public enum NewsResearcherDefinition {
    public static let id = "NewsResearcher"
    public static let versions = ["1.0.0"]

    public static func directory(version: String) throws -> URL {
        guard versions.contains(version),
              let url = Bundle.module.url(forResource: version, withExtension: nil) else {
            throw DefinitionError.unknownVersion
        }
        return url
    }

    public enum DefinitionError: Error { case unknownVersion }
}
