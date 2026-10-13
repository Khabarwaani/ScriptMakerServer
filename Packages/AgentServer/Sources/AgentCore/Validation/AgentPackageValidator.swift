import Foundation
import CryptoKit

/// Represents build-time validation metadata for an agent version's resources.
public struct AgentValidationMetadata: Codable, Sendable, Equatable {
    public struct VersionMetadata: Codable, Sendable, Equatable {
        public let version: String
        public let resourceHashes: [String: String] // relative resource path -> SHA256 hex string

        public init(version: String, resourceHashes: [String: String]) {
            self.version = version
            self.resourceHashes = resourceHashes
        }
    }

    public let agentId: String
    public let versions: [VersionMetadata]

    public init(agentId: String, versions: [VersionMetadata]) {
        self.agentId = agentId
        self.versions = versions
    }
}

/// Validates agent packages, resource completeness, schemas, and examples at build time.
public enum AgentPackageValidator {
    public struct ValidationError: Error, CustomStringConvertible {
        public let agent: String
        public let version: String?
        public let file: String?
        public let location: String?
        public let message: String

        public init(agent: String, version: String? = nil, file: String? = nil, location: String? = nil, message: String) {
            self.agent = agent
            self.version = version
            self.file = file
            self.location = location
            self.message = message
        }

        public var description: String {
            var parts: [String] = []
            if let file = file {
                parts.append(file)
            } else {
                parts.append(agent)
            }
            if let loc = location {
                parts.append("[\(loc)]")
            }
            let prefix = parts.joined(separator: ": ")
            let versionInfo = version.map { " (version \($0))" } ?? ""
            return "\(prefix): error: [Agent: \(agent)\(versionInfo)] \(message)"
        }
    }

    /// Computes SHA256 hex digest for data.
    public static func sha256Hex(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Computes SHA256 hex digest for a file URL.
    public static func sha256Hex(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        return sha256Hex(for: data)
    }

    /// Validates an agent package directory and returns its `AgentValidationMetadata`.
    public static func validate(packageDirectory: URL) throws -> AgentValidationMetadata {
        let agentId = packageDirectory.lastPathComponent
        guard AgentRegistry.validID(agentId) else {
            throw ValidationError(agent: agentId, message: "Invalid agent directory name '\(agentId)'. Agent IDs must match ^[A-Za-z][A-Za-z0-9_]*$")
        }

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

        // Sort versions by SemVer
        versionDirs.sort { (a, b) -> Bool in
            guard let va = SemanticVersion(a.lastPathComponent), let vb = SemanticVersion(b.lastPathComponent) else { return false }
            return va < vb
        }

        guard !versionDirs.isEmpty else {
            throw ValidationError(agent: agentId, message: "Agent package '\(agentId)' contains no valid semantic version directories.")
        }

        var validatedVersions: [AgentValidationMetadata.VersionMetadata] = []

        for versionDir in versionDirs {
            let versionStr = versionDir.lastPathComponent
            var resourceHashes: [String: String] = [:]

            // 1. role.md
            let roleFile = versionDir.appendingPathComponent("role.md")
            guard fileManager.fileExists(atPath: roleFile.path) else {
                throw ValidationError(agent: agentId, version: versionStr, file: roleFile.path, message: "Missing required resource 'role.md'")
            }
            let roleContent = try String(contentsOf: roleFile, encoding: .utf8)
            guard roleContent.contains(".") else {
                throw ValidationError(agent: agentId, version: versionStr, file: roleFile.path, message: "role.md must describe a complete role ending in a period or containing sentences.")
            }
            resourceHashes["role.md"] = try sha256Hex(for: roleFile)

            // 2. instructions.md (or instructions.*.md)
            let versionEntries = try fileManager.contentsOfDirectory(at: versionDir, includingPropertiesForKeys: nil)
            let instructionFiles = versionEntries.filter {
                $0.lastPathComponent == "instructions.md" || ($0.lastPathComponent.hasPrefix("instructions.") && $0.pathExtension == "md")
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }

            guard !instructionFiles.isEmpty else {
                throw ValidationError(agent: agentId, version: versionStr, file: versionDir.path, message: "Missing required instructions resource 'instructions.md'")
            }

            for instrFile in instructionFiles {
                let content = try String(contentsOf: instrFile, encoding: .utf8)
                guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ValidationError(agent: agentId, version: versionStr, file: instrFile.path, message: "Instructions file '\(instrFile.lastPathComponent)' cannot be empty.")
                }
                resourceHashes[instrFile.lastPathComponent] = try sha256Hex(for: instrFile)
            }

            // 3. output.schema.json
            let outputSchemaFile = versionDir.appendingPathComponent("output.schema.json")
            guard fileManager.fileExists(atPath: outputSchemaFile.path) else {
                throw ValidationError(agent: agentId, version: versionStr, file: outputSchemaFile.path, message: "Missing required resource 'output.schema.json'")
            }
            let outputSchemaData = try Data(contentsOf: outputSchemaFile)
            let outputSchemaJSON: JSONValue
            do {
                guard let text = String(data: outputSchemaData, encoding: .utf8) else {
                    throw ValidationError(agent: agentId, version: versionStr, file: outputSchemaFile.path, message: "output.schema.json is not valid UTF-8 text.")
                }
                outputSchemaJSON = try JSONValue.parse(text)
            } catch let err as AgentError {
                throw ValidationError(agent: agentId, version: versionStr, file: outputSchemaFile.path, location: "JSON syntax", message: err.message)
            } catch {
                throw ValidationError(agent: agentId, version: versionStr, file: outputSchemaFile.path, location: "JSON syntax", message: error.localizedDescription)
            }

            // Check schema structure and assertions
            do {
                try OutputValidator.checkSchema(outputSchemaJSON)
            } catch let err as AgentError {
                throw ValidationError(agent: agentId, version: versionStr, file: outputSchemaFile.path, location: "schema validation", message: err.message)
            } catch {
                throw ValidationError(agent: agentId, version: versionStr, file: outputSchemaFile.path, location: "schema validation", message: error.localizedDescription)
            }

            // Validate schema documentation examples if present
            if let examples = outputSchemaJSON["examples"]?.array {
                for (idx, example) in examples.enumerated() {
                    do {
                        try OutputValidator.validate(example, schema: outputSchemaJSON)
                    } catch {
                        throw ValidationError(
                            agent: agentId,
                            version: versionStr,
                            file: outputSchemaFile.path,
                            location: "examples[\(idx)]",
                            message: "Example does not conform to output.schema.json: \(error)"
                        )
                    }
                }
            }
            resourceHashes["output.schema.json"] = try sha256Hex(for: outputSchemaFile)

            // 4. optional input.schema.json
            let inputSchemaFile = versionDir.appendingPathComponent("input.schema.json")
            if fileManager.fileExists(atPath: inputSchemaFile.path) {
                let inputSchemaData = try Data(contentsOf: inputSchemaFile)
                let inputSchemaJSON: JSONValue
                do {
                    guard let text = String(data: inputSchemaData, encoding: .utf8) else {
                        throw ValidationError(agent: agentId, version: versionStr, file: inputSchemaFile.path, message: "input.schema.json is not valid UTF-8 text.")
                    }
                    inputSchemaJSON = try JSONValue.parse(text)
                } catch let err as AgentError {
                    throw ValidationError(agent: agentId, version: versionStr, file: inputSchemaFile.path, location: "JSON syntax", message: err.message)
                } catch {
                    throw ValidationError(agent: agentId, version: versionStr, file: inputSchemaFile.path, location: "JSON syntax", message: error.localizedDescription)
                }

                do {
                    try OutputValidator.checkSchema(inputSchemaJSON)
                } catch let err as AgentError {
                    throw ValidationError(agent: agentId, version: versionStr, file: inputSchemaFile.path, location: "schema validation", message: err.message)
                } catch {
                    throw ValidationError(agent: agentId, version: versionStr, file: inputSchemaFile.path, location: "schema validation", message: error.localizedDescription)
                }

                if let examples = inputSchemaJSON["examples"]?.array {
                    for (idx, example) in examples.enumerated() {
                        do {
                            _ = try InputValidator.prepare(example, schema: inputSchemaJSON, agentID: agentId, version: versionStr)
                        } catch {
                            throw ValidationError(
                                agent: agentId,
                                version: versionStr,
                                file: inputSchemaFile.path,
                                location: "examples[\(idx)]",
                                message: "Example does not conform to input.schema.json: \(error)"
                            )
                        }
                    }
                }
                resourceHashes["input.schema.json"] = try sha256Hex(for: inputSchemaFile)
            }

            validatedVersions.append(AgentValidationMetadata.VersionMetadata(version: versionStr, resourceHashes: resourceHashes))
        }

        return AgentValidationMetadata(agentId: agentId, versions: validatedVersions)
    }

    /// Validates all agent packages found within `agentsDirectory` and returns catalog metadata.
    public static func validateAll(in agentsDirectory: URL) throws -> [AgentValidationMetadata] {
        let fileManager = FileManager.default
        let entries = try fileManager.contentsOfDirectory(at: agentsDirectory, includingPropertiesForKeys: [.isDirectoryKey])
        var results: [AgentValidationMetadata] = []

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue {
                // If it's an agent package directory
                let packageSwift = entry.appendingPathComponent("Package.swift")
                if fileManager.fileExists(atPath: packageSwift.path) {
                    let metadata = try validate(packageDirectory: entry)
                    results.append(metadata)
                }
            }
        }
        return results
    }
}
