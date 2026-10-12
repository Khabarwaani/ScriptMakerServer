import Foundation
import NewsResearcher
import ScriptWriter

public protocol AgentPackageContract: Sendable {
    static var id: String { get }
    static var versions: [String] { get }
    static func directory(version: String) throws -> URL
    static func role(version: String) throws -> String
    static func instructions(version: String) throws -> String
    static func outputSchema(version: String) throws -> String
    static func inputSchema(version: String) throws -> String?
}

extension NewsResearcherDefinition: AgentPackageContract {}
extension ScriptWriterDefinition: AgentPackageContract {}
