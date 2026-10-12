import Foundation

/// Holds the build-generated agent documentation metadata catalog.
public enum GeneratedAgentDocumentationCatalog {
    public nonisolated(unsafe) static var documentation: [AgentDocumentationMetadata] = []

    public static func doc(for agentId: String) -> AgentDocumentationMetadata? {
        documentation.first(where: { $0.agentId == agentId })
    }
}
