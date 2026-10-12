import Foundation
import NewsResearcher
import ScriptWriter

public struct AgentDefinition: Sendable {
    public let id: String
    public let version: String
    public let role: String
    public let instructions: String
    public let outputSchema: JSONValue
    public let inputSchema: JSONValue?
}

public struct AgentSummary: Codable, Sendable {
    public let id: String
    public let versions: [String]
    public let latest: String?
    public let definitions: [AgentVersionDetails]
}

public struct AgentVersionDetails: Codable, Sendable {
    public let version: String
    public let role: String
    public let instructions: String
    public let input_schema: JSONValue?
    public let output_schema: JSONValue
}

public actor AgentRegistry {
    public static let registeredPackages: [any AgentPackageContract.Type] = [
        NewsResearcherDefinition.self,
        ScriptWriterDefinition.self,
    ]

    private let packages: [any AgentPackageContract.Type]
    private let root: URL?
    private var cache: [String: AgentDefinition] = [:]

    public init(
        packages: [any AgentPackageContract.Type] = AgentRegistry.registeredPackages,
        root: URL? = nil
    ) {
        self.packages = packages
        self.root = root?.standardizedFileURL.resolvingSymlinksInPath()
    }

    public init(root: URL) {
        self.init(packages: Self.registeredPackages, root: root)
    }

    public func list() -> [AgentSummary] {
        let definitions = discover()
        return Dictionary(grouping: definitions, by: \.id).map { id, values in
            let versions = values.compactMap { SemanticVersion($0.version) }.sorted {
                $0 == $1 ? $0.raw < $1.raw : $0 < $1
            }
            let details = versions.compactMap { version -> AgentVersionDetails? in
                guard let definition = values.first(where: { $0.version == version.raw }) else { return nil }
                return AgentVersionDetails(
                    version: definition.version, role: definition.role, instructions: definition.instructions,
                    input_schema: definition.inputSchema, output_schema: definition.outputSchema)
            }
            return AgentSummary(
                id: id, versions: versions.map(\.raw), latest: versions.last(where: \.stable)?.raw,
                definitions: details)
        }.sorted { $0.id < $1.id }
    }

    public func resolve(id: String, version: String?) throws -> AgentDefinition {
        guard Self.validID(id) else { throw AgentError("invalid_request", "Agent ID is invalid.") }
        if let version, SemanticVersion(version) == nil {
            throw AgentError("invalid_request", "Version must use semantic versioning.")
        }
        let definitions = discover().filter { $0.id == id }
        guard !definitions.isEmpty else {
            if packages.contains(where: { $0.id == id }) {
                throw AgentError("invalid_agent_definition", "The agent has no valid available definitions.")
            }
            if let root = self.root,
                safeURL(root.appendingPathComponent(id)) != nil,
                FileManager.default.fileExists(atPath: root.appendingPathComponent(id).path)
            {
                throw AgentError("invalid_agent_definition", "The agent has no valid available definitions.")
            }
            throw AgentError("unknown_agent", "The requested agent does not exist.")
        }
        let selected =
            version ?? definitions.compactMap { SemanticVersion($0.version) }.filter(\.stable).max()?.raw
        guard let selected, let definition = definitions.first(where: { $0.version == selected }) else {
            throw AgentError(
                "unknown_version", "The requested version or a stable default version is unavailable.")
        }
        return definition
    }

    public static func validID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z][A-Za-z0-9_]*$"#, options: .regularExpression) == value.startIndex..<value.endIndex
    }

    private func safeURL(_ url: URL) -> URL? {
        guard let root = self.root else { return nil }
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        return resolved.path.hasPrefix(root.path + "/") ? resolved : nil
    }

    private func discover() -> [AgentDefinition] {
        var found: [AgentDefinition] = []
        for package in packages where Self.validID(package.id) {
            let sortedVersions = package.versions.compactMap(SemanticVersion.init).sorted {
                $0 == $1 ? $0.raw < $1.raw : $0 < $1
            }
            for semver in sortedVersions {
                let version = semver.raw
                let key = package.id + "/" + version
                if let cached = cache[key] {
                    found.append(cached)
                    continue
                }
                do {
                    let role = try package.role(version: version)
                    guard role.contains(".") else { continue }
                    let instructions = try package.instructions(version: version)
                    guard !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    let outputSchemaText = try package.outputSchema(version: version)
                    let schema = try JSONValue.parse(outputSchemaText)
                    try OutputValidator.checkSchema(schema)
                    let inputSchema: JSONValue?
                    if let inputSchemaText = try package.inputSchema(version: version) {
                        let parsed = try JSONValue.parse(inputSchemaText)
                        try OutputValidator.checkSchema(parsed)
                        inputSchema = parsed
                    } else {
                        inputSchema = nil
                    }
                    let definition = AgentDefinition(
                        id: package.id, version: version, role: role,
                        instructions: instructions, outputSchema: schema, inputSchema: inputSchema)
                    cache[key] = definition
                    found.append(definition)
                } catch { continue }
            }
        }
        return found
    }
}
