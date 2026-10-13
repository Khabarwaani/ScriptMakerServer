import Foundation
import NewsResearcher
import ScriptRefiner
import DialogueRefiner
import ReelIdeaGenerator

public protocol AgentPackageContract: Sendable {
    static var id: String { get }
    static var name: String { get }
    static var versions: [String] { get }
    static func directory(version: String) throws -> URL
    static func role(version: String) throws -> String
    static func instructions(version: String) throws -> String
    static func outputSchema(version: String) throws -> String
    static func inputSchema(version: String) throws -> String?
    static func readme() -> String
    static func documentation(version: String) -> AgentVersionDocumentation?
}

extension AgentPackageContract {
    public static var name: String { id }

    public static func readme() -> String {
        GeneratedAgentDocumentationCatalog.doc(for: id)?.readme ?? ""
    }

    public static func documentation(version: String) -> AgentVersionDocumentation? {
        GeneratedAgentDocumentationCatalog.doc(for: id)?.versions.first(where: { $0.version == version })
    }
}

extension NewsResearcherDefinition: AgentPackageContract {
    public static var name: String { "News Researcher" }
}
extension ScriptRefinerDefinition: AgentPackageContract {
    public static var name: String { "Script Refiner" }
}
extension DialogueRefinerDefinition: AgentPackageContract {
    public static var name: String { "Dialogue Refiner" }
}
extension ReelIdeaGeneratorDefinition: AgentPackageContract {
    public static var name: String { "Reel Idea Generator" }
}
