import Foundation

/// Structured documentation metadata for an agent version.
public struct AgentVersionDocumentation: Codable, Sendable, Equatable {
    public let version: String
    public let role: String
    public let instructions: String
    public let inputSchema: JSONValue?
    public let outputSchema: JSONValue
    public let inputExamples: [JSONValue]
    public let outputExamples: [JSONValue]
    public let constraints: [String]
    public let notes: String?

    public init(
        version: String,
        role: String,
        instructions: String,
        inputSchema: JSONValue?,
        outputSchema: JSONValue,
        inputExamples: [JSONValue] = [],
        outputExamples: [JSONValue] = [],
        constraints: [String] = [],
        notes: String? = nil
    ) {
        self.version = version
        self.role = role
        self.instructions = instructions
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.inputExamples = inputExamples
        self.outputExamples = outputExamples
        self.constraints = constraints
        self.notes = notes
    }
}

/// Structured documentation metadata for an entire agent package.
public struct AgentDocumentationMetadata: Codable, Sendable, Equatable {
    public let agentId: String
    public let readme: String
    public let versions: [AgentVersionDocumentation]

    public init(agentId: String, readme: String, versions: [AgentVersionDocumentation]) {
        self.agentId = agentId
        self.readme = readme
        self.versions = versions
    }
}

/// Generates documentation and Markdown READMEs from package declarations and resources.
public enum AgentDocumentationGenerator {

    /// Derives constraints described in schema objects.
    public static func extractConstraints(from schema: JSONValue?) -> [String] {
        guard let schema = schema, let obj = schema.object else { return [] }
        var constraints: [String] = []

        if let required = obj["required"]?.array?.compactMap(\.string), !required.isEmpty {
            constraints.append("Required fields: " + required.joined(separator: ", "))
        }
        if let additional = obj["additionalProperties"]?.bool, !additional {
            constraints.append("Strict schema: additional properties are not permitted.")
        }
        if let minItems = obj["minItems"]?.number {
            constraints.append("Minimum items: \(Int(minItems))")
        }
        if let maxItems = obj["maxItems"]?.number {
            constraints.append("Maximum items: \(Int(maxItems))")
        }
        if let minLength = obj["minLength"]?.number {
            constraints.append("Minimum length: \(Int(minLength))")
        }
        if let min = obj["minimum"]?.number {
            constraints.append("Minimum value: \(min)")
        }
        if let max = obj["maximum"]?.number {
            constraints.append("Maximum value: \(max)")
        }
        return constraints
    }

    /// Generates markdown README content from package directory and parsed version documentation.
    public static func generateReadme(agentId: String, versions: [AgentVersionDocumentation]) -> String {
        var doc = "# \(agentId)\n\n"
        doc += "Independent Swift package with provider-independent agent definitions.\n\n"
        doc += "Generated from the versioned resources. From the repository root, refresh with `swift run --package-path Packages/AgentServer AgentTools docs`; verify with `AgentTools docs --check`. Put authored notes in a version's `notes.md` rather than editing this generated file.\n\n"
        doc += "## Server integration\n\n"
        doc += "The server must link this Swift package, adapt it to `AgentPackageContract`, and explicitly register it in `AgentRegistry.registeredPackages`. Version resources are compiled and validated at build time. Rebuild the server after adding or changing declared versions; adding Markdown directories alone does not make an agent available.\n\n"
        doc += "Test this package from the repository root:\n\n```sh\nswift test --package-path Packages/AgentServer/Agents/\(agentId)\n```\n\n"
        doc += "## HTTP execution\n\n"
        doc += "`GET /agents` returns only agent IDs, display names and available versions. `POST /execute` returns one schema-validated JSON value or a structured error by default; `status=false` can be omitted. Use `POST /execute?status=true` for lifecycle/progress SSE and one validated final result. Raw provider text stays internal. Select this agent on `/help` or `/try`; those pages include the status checkbox and Copy controls. Full contracts are available from `/openapi.json`.\n\n"

        if let latest = versions.last(where: { SemanticVersion($0.version)?.stable == true }) ?? versions.last {
            doc += "## Responsibility\n\n\(latest.role)\n\n"
        }

        doc += "## Available Versions\n\n"
        for ver in versions {
            doc += "### Version \(ver.version)\n\n"
            doc += "**Role:** \(ver.role)\n\n"
            if let notes = ver.notes, !notes.isEmpty {
                doc += "**Notes:**\n\(notes)\n\n"
            }
            if !ver.constraints.isEmpty {
                doc += "**Constraints:**\n"
                for c in ver.constraints {
                    doc += "- \(c)\n"
                }
                doc += "\n"
            }
            doc += "#### Instructions\n\n\(ver.instructions)\n\n"
            if let schema = ver.inputSchema {
                doc += "#### Input JSON Schema\n\n" + jsonBlock(schema) + "\n"
            } else {
                doc += "#### Input\n\nAny JSON object; this version does not declare an input schema.\n\n"
            }
            doc += "#### Output JSON Schema\n\n" + jsonBlock(ver.outputSchema) + "\n"
            if !ver.inputExamples.isEmpty {
                doc += "#### Example Input\n\n" + jsonBlock(ver.inputExamples[0]) + "\n"
            }
            if !ver.outputExamples.isEmpty {
                doc += "#### Example Output (Illustrative Only)\n\n" + jsonBlock(ver.outputExamples[0]) + "\n"
            }
        }

        return doc.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func jsonBlock(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let text = (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
        return "```json\n" + text + "\n```\n"
    }

    /// Generates `AgentDocumentationMetadata` for an agent package directory.
    public static func generate(packageDirectory: URL) throws -> AgentDocumentationMetadata {
        let agentId = packageDirectory.lastPathComponent
        let fileManager = FileManager.default
        let entries = try fileManager.contentsOfDirectory(at: packageDirectory, includingPropertiesForKeys: [.isDirectoryKey])

        var versionDirs: [URL] = []
        for entry in entries {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue {
                let name = entry.lastPathComponent
                if SemanticVersion(name) != nil {
                    versionDirs.append(entry)
                }
            }
        }

        versionDirs.sort { (a, b) -> Bool in
            guard let va = SemanticVersion(a.lastPathComponent), let vb = SemanticVersion(b.lastPathComponent) else { return false }
            return va == vb ? va.raw < vb.raw : va < vb
        }

        var versionDocs: [AgentVersionDocumentation] = []

        for versionDir in versionDirs {
            let versionStr = versionDir.lastPathComponent

            // role
            let roleFile = versionDir.appendingPathComponent("role.md")
            let role = (try? String(contentsOf: roleFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // instructions
            let versionEntries = try fileManager.contentsOfDirectory(at: versionDir, includingPropertiesForKeys: nil)
            let instructionFiles = versionEntries.filter {
                $0.lastPathComponent == "instructions.md" || ($0.lastPathComponent.hasPrefix("instructions.") && $0.pathExtension == "md")
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }

            let instructions = try instructionFiles.map {
                try String(contentsOf: $0, encoding: .utf8)
            }.joined(separator: "\n\n")

            // output schema & examples
            let outputSchemaFile = versionDir.appendingPathComponent("output.schema.json")
            let outputSchemaText = (try? String(contentsOf: outputSchemaFile, encoding: .utf8)) ?? "{}"
            let outputSchema = (try? JSONValue.parse(outputSchemaText)) ?? .object([:])
            let outputExamples = outputSchema["examples"]?.array ?? []

            // input schema & examples
            let inputSchemaFile = versionDir.appendingPathComponent("input.schema.json")
            let inputSchema: JSONValue?
            let inputExamples: [JSONValue]
            if fileManager.fileExists(atPath: inputSchemaFile.path),
               let text = try? String(contentsOf: inputSchemaFile, encoding: .utf8),
               let parsed = try? JSONValue.parse(text) {
                inputSchema = parsed
                inputExamples = parsed["examples"]?.array ?? []
            } else {
                inputSchema = nil
                inputExamples = []
            }

            // Optional authored notes in version directory or package directory
            var notes: String? = nil
            let notesFile = versionDir.appendingPathComponent("notes.md")
            if fileManager.fileExists(atPath: notesFile.path),
               let content = try? String(contentsOf: notesFile, encoding: .utf8) {
                notes = content.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            var constraints = extractConstraints(from: outputSchema)
            if let inSchema = inputSchema {
                constraints.append(contentsOf: extractConstraints(from: inSchema))
            }

            versionDocs.append(AgentVersionDocumentation(
                version: versionStr,
                role: role,
                instructions: instructions,
                inputSchema: inputSchema,
                outputSchema: outputSchema,
                inputExamples: inputExamples,
                outputExamples: outputExamples,
                constraints: constraints,
                notes: notes
            ))
        }

        let readme = generateReadme(agentId: agentId, versions: versionDocs)
        return AgentDocumentationMetadata(agentId: agentId, readme: readme, versions: versionDocs)
    }

    /// Generates documentation metadata for all agents in `agentsDirectory`.
    public static func generateAll(in agentsDirectory: URL) throws -> [AgentDocumentationMetadata] {
        let fileManager = FileManager.default
        let entries = try fileManager.contentsOfDirectory(at: agentsDirectory, includingPropertiesForKeys: [.isDirectoryKey])
        var results: [AgentDocumentationMetadata] = []

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue {
                let packageSwift = entry.appendingPathComponent("Package.swift")
                if fileManager.fileExists(atPath: packageSwift.path) {
                    let docMeta = try generate(packageDirectory: entry)
                    results.append(docMeta)
                }
            }
        }
        return results
    }

    /// Refresh checked-in READMEs, or report drift without writing in check-only mode.
    public static func synchronizeReadmes(in agentsDirectory: URL, checkOnly: Bool = false) throws -> [String] {
        _ = try AgentPackageValidator.validateAll(in: agentsDirectory)
        var changed: [String] = []
        for documentation in try generateAll(in: agentsDirectory) {
            let package = agentsDirectory.appendingPathComponent(documentation.agentId, isDirectory: true)
            let readme = package.appendingPathComponent("README.md")
            guard readme.resolvingSymlinksInPath().path.hasPrefix(package.resolvingSymlinksInPath().path + "/") else {
                throw AgentError("invalid_request", "Package README must remain within its package directory.")
            }
            if (try? String(contentsOf: readme, encoding: .utf8)) != documentation.readme {
                changed.append(documentation.agentId)
                if !checkOnly {
                    try documentation.readme.write(to: readme, atomically: true, encoding: .utf8)
                }
            }
        }
        return changed
    }
}
