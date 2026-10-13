import Foundation
import NewsResearcher
import ScriptRefiner
import DialogueRefiner
import ReelIdeaGenerator
import DialogueGenerator
import ThemeMixer

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
    public let name: String
    public let versions: [String]
    public let latest: String?
    public let definitions: [AgentVersionDetails]
    public let readme: String?

    public init(id: String, versions: [String], latest: String?, definitions: [AgentVersionDetails], readme: String? = nil, name: String? = nil) {
        self.id = id
        self.name = name ?? id
        self.versions = versions
        self.latest = latest
        self.definitions = definitions
        self.readme = readme
    }
}

public struct AgentListItem: Codable, Sendable {
    public let id: String
    public let name: String
    public let versions: [String]
}

public struct AgentVersionDetails: Codable, Sendable {
    public let version: String
    public let role: String
    public let instructions: String
    public let input_schema: JSONValue?
    public let output_schema: JSONValue
    public let notes: String?

    public init(version: String, role: String, instructions: String, input_schema: JSONValue?, output_schema: JSONValue, notes: String? = nil) {
        self.version = version
        self.role = role
        self.instructions = instructions
        self.input_schema = input_schema
        self.output_schema = output_schema
        self.notes = notes
    }
}

public actor AgentRegistry {
    public static let registeredPackages: [any AgentPackageContract.Type] = [
        NewsResearcherDefinition.self,
        ScriptRefinerDefinition.self,
        DialogueRefinerDefinition.self,
        ReelIdeaGeneratorDefinition.self,
        DialogueGeneratorDefinition.self,
        ThemeMixerDefinition.self,
    ]

    private let packages: [any AgentPackageContract.Type]
    private let validationMetadata: [AgentValidationMetadata]?
    private let root: URL?
    private var cache: [String: AgentDefinition] = [:]

    public init(
        packages: [any AgentPackageContract.Type] = AgentRegistry.registeredPackages,
        validationMetadata: [AgentValidationMetadata]? = nil,
        root: URL? = nil
    ) {
        self.packages = packages
        self.validationMetadata = validationMetadata
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
            let matchingPackage = packages.first(where: { $0.id == id })
            let details = versions.compactMap { version -> AgentVersionDetails? in
                guard let definition = values.first(where: { $0.version == version.raw }) else { return nil }
                let notes = matchingPackage?.documentation(version: version.raw)?.notes
                return AgentVersionDetails(
                    version: definition.version, role: definition.role, instructions: definition.instructions,
                    input_schema: definition.inputSchema, output_schema: definition.outputSchema,
                    notes: notes)
            }
            let readme = matchingPackage?.readme()
            return AgentSummary(
                id: id, versions: versions.map(\.raw), latest: versions.last(where: \.stable)?.raw,
                definitions: details, readme: readme, name: matchingPackage?.name)
        }.sorted { $0.id < $1.id }
    }

    /// Lightweight discovery without loading package documentation or probing providers.
    public func availableAgents() -> [AgentListItem] {
        Dictionary(grouping: discover(), by: \.id).map { id, definitions in
            let versions = definitions.compactMap { SemanticVersion($0.version) }.sorted {
                $0 == $1 ? $0.raw < $1.raw : $0 < $1
            }
            return AgentListItem(
                id: id, name: packages.first(where: { $0.id == id })?.name ?? id,
                versions: versions.map(\.raw))
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

                // If validation metadata is provided, verify against it
                if let validationMetadata = self.validationMetadata {
                    guard let agentMeta = validationMetadata.first(where: { $0.agentId == package.id }),
                          let versionMeta = agentMeta.versions.first(where: { $0.version == version }) else {
                        // Unvalidated version or agent
                        continue
                    }

                    // Check resource completeness and hashes
                    guard let dir = try? package.directory(version: version) else { continue }
                    var hashesMatch = true
                    for (resourceName, expectedHash) in versionMeta.resourceHashes {
                        let fileURL = dir.appendingPathComponent(resourceName)
                        guard let computedHash = try? AgentPackageValidator.sha256Hex(for: fileURL),
                              computedHash == expectedHash else {
                            hashesMatch = false
                            break
                        }
                    }
                    guard hashesMatch else { continue }
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
