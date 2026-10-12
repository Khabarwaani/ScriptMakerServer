import Foundation

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
    private let root: URL
    private var cache: [String: AgentDefinition] = [:]
    public init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }

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
            if safeURL(root.appendingPathComponent(id)) != nil
                && FileManager.default.fileExists(atPath: root.appendingPathComponent(id).path)
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
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        return resolved.path.hasPrefix(root.path + "/") ? resolved : nil
    }

    private func discover() -> [AgentDefinition] {
        guard
            let directories = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        else { return [] }
        var found: [AgentDefinition] = []
        for directory in directories where Self.validID(directory.lastPathComponent) {
            guard let safeDirectory = safeURL(directory),
                let versions = try? FileManager.default.contentsOfDirectory(
                    at: safeDirectory, includingPropertiesForKeys: [.isDirectoryKey],
                    options: .skipsHiddenFiles)
            else { continue }
            for version in versions where SemanticVersion(version.lastPathComponent) != nil {
                let key = directory.lastPathComponent + "/" + version.lastPathComponent
                guard safeURL(version) != nil else { continue }
                if let cached = cache[key] {
                    found.append(cached)
                    continue
                }
                do {
                    let role = try read(version.appendingPathComponent("role.md"))
                    let instructionFiles = try FileManager.default.contentsOfDirectory(
                        at: version, includingPropertiesForKeys: nil
                    )
                    .filter {
                        $0.lastPathComponent == "instructions.md"
                            || ($0.lastPathComponent.hasPrefix("instructions.") && $0.pathExtension == "md")
                    }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                    guard !instructionFiles.isEmpty, role.contains(".") else { continue }
                    let instructions = try instructionFiles.map(read).joined(separator: "\n\n")
                    let schema = try JSONValue.parse(
                        read(version.appendingPathComponent("output.schema.json")))
                    try OutputValidator.checkSchema(schema)
                    let inputURL = version.appendingPathComponent("input.schema.json")
                    let inputSchema =
                        FileManager.default.fileExists(atPath: inputURL.path)
                        ? try JSONValue.parse(read(inputURL)) : nil
                    if let inputSchema { try OutputValidator.checkSchema(inputSchema) }
                    let definition = AgentDefinition(
                        id: directory.lastPathComponent, version: version.lastPathComponent, role: role,
                        instructions: instructions, outputSchema: schema, inputSchema: inputSchema)
                    cache[key] = definition
                    found.append(definition)
                } catch { continue }
            }
        }
        return found
    }

    private func read(_ url: URL) throws -> String {
        guard let safe = safeURL(url),
            let size = try safe.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576
        else {
            throw AgentError("invalid_agent_definition", "Definition file is unavailable or too large.")
        }
        let text = try String(contentsOf: safe, encoding: .utf8)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError("invalid_agent_definition", "Definition file is empty.")
        }
        return text
    }
}
