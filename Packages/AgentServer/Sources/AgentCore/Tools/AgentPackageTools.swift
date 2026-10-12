import Foundation

public enum AgentPackageTools {
    public static func create(id: String, version: String = "1.0.0", root: URL) throws {
        guard AgentRegistry.validID(id), SemanticVersion(version) != nil else {
            throw AgentError("invalid_request", "Agent ID must be a Swift identifier and version must be valid SemVer.")
        }
        let package = root.standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent(id, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: package.path) else {
            throw AgentError("agent_already_exists", "The package already exists. Add a new version instead of overwriting it.")
        }
        let definition = package.appendingPathComponent(version, isDirectory: true)
        try FileManager.default.createDirectory(at: definition, withIntermediateDirectories: true)
        do {
            try write("You are the \(id) agent responsible for processing supplied JSON input and returning a structured result.", to: definition.appendingPathComponent("role.md"))
            try write("# Instructions\n\nProcess supplied JSON data and return one object matching output.schema.json. Do not expose secrets.", to: definition.appendingPathComponent("instructions.md"))
            try write(#"{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,"required":["result"],"properties":{"result":{"type":"string"}}}"#, to: definition.appendingPathComponent("output.schema.json"))
            try packageFiles(id: id, version: version, package: package)
        } catch {
            try? FileManager.default.removeItem(at: package)
            throw error
        }
    }

    public static func addVersion(id: String, version: String, sourceVersion: String, root: URL) throws {
        guard AgentRegistry.validID(id), SemanticVersion(version) != nil, SemanticVersion(sourceVersion) != nil else {
            throw AgentError("invalid_request", "Agent ID and versions are invalid.")
        }
        let package = root.standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent(id, isDirectory: true).resolvingSymlinksInPath()
        let source = package.appendingPathComponent(sourceVersion, isDirectory: true)
        let destination = package.appendingPathComponent(version, isDirectory: true)
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard source.resolvingSymlinksInPath().path.hasPrefix(resolvedRoot), destination.resolvingSymlinksInPath().path.hasPrefix(resolvedRoot) else {
            throw AgentError("invalid_request", "Agent paths must remain within the configured root.")
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw AgentError("version_already_exists", "That version already exists and cannot be overwritten.")
        }
        try FileManager.default.copyItem(at: source, to: destination)
        try writeManifest(id: id, package: package)
    }

    public static func check(root: URL) throws -> [String] {
        var issues: [String] = []
        let packages = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        for package in packages where (try? package.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let id = package.lastPathComponent
            guard AgentRegistry.validID(id), package.resolvingSymlinksInPath().path.hasPrefix(resolvedRoot) else {
                issues.append("\(id): invalid package identifier or path"); continue
            }
            for name in ["Package.swift", "README.md", "Sources/\(id)/\(id).swift", "Tests/\(id)Tests/DefinitionTests.swift"] {
                if !FileManager.default.fileExists(atPath: package.appendingPathComponent(name).path) { issues.append("\(id): missing \(name)") }
            }
            let versions = try FileManager.default.contentsOfDirectory(at: package, includingPropertiesForKeys: nil).filter { SemanticVersion($0.lastPathComponent) != nil }
            if versions.isEmpty { issues.append("\(id): no semantic versions") }
            for version in versions {
                for name in ["role.md", "instructions.md", "output.schema.json"] {
                    let file = version.appendingPathComponent(name)
                    guard file.resolvingSymlinksInPath().path.hasPrefix(resolvedRoot),
                          let text = try? String(contentsOf: file, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        issues.append("\(id)/\(version.lastPathComponent): missing, empty or unsafe \(name)"); continue
                    }
                    if name == "role.md", !text.contains(".") { issues.append("\(id): role must be a complete sentence") }
                    if name == "output.schema.json" {
                        do { try OutputValidator.checkSchema(JSONValue.parse(text)) }
                        catch { issues.append("\(id)/\(version.lastPathComponent): invalid or unsupported output schema") }
                    }
                }
                let input = version.appendingPathComponent("input.schema.json")
                if FileManager.default.fileExists(atPath: input.path) {
                    do { try OutputValidator.checkSchema(JSONValue.parse(String(contentsOf: input, encoding: .utf8))) }
                    catch { issues.append("\(id)/\(version.lastPathComponent): invalid input schema") }
                }
            }
        }
        return issues.sorted()
    }

    private static func writeManifest(id: String, package: URL) throws {
        let resources = try FileManager.default.contentsOfDirectory(at: package, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent).filter { SemanticVersion($0) != nil }.sorted().map { ".copy(\"\($0)\")" }.joined(separator: ", ")
        try write("""
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(
            name: "\(id)", platforms: [.macOS(.v14)],
            products: [.library(name: "\(id)", targets: ["\(id)"])],
            targets: [
                .target(name: "\(id)", path: ".", exclude: ["Tests", "README.md"],
                        sources: ["Sources/\(id)/\(id).swift"], resources: [\(resources)]),
                .testTarget(name: "\(id)Tests", dependencies: ["\(id)"])
            ]
        )
        """, to: package.appendingPathComponent("Package.swift"))
    }

    private static func packageFiles(id: String, version: String, package: URL) throws {
        try writeManifest(id: id, package: package)
        let source = package.appendingPathComponent("Sources/\(id)", isDirectory: true)
        let tests = package.appendingPathComponent("Tests/\(id)Tests", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try write("""
        import Foundation
        public enum \(id)Definition {
            public static let id = "\(id)"
            public static func directory(version: String) throws -> URL {
                guard version.range(of: #"^[0-9A-Za-z.+-]+$"#, options: .regularExpression) != nil,
                      let url = Bundle.module.url(forResource: version, withExtension: nil),
                      FileManager.default.fileExists(atPath: url.appendingPathComponent("role.md").path) else {
                    throw DefinitionError.unknownVersion
                }
                return url
            }
            public enum DefinitionError: Error { case unknownVersion }
        }
        """, to: source.appendingPathComponent("\(id).swift"))
        try write("""
        import Foundation
        import Testing
        import \(id)
        @Test func definitionResourcesAreComplete() throws {
            let directory = try \(id)Definition.directory(version: "\(version)")
            for name in ["role.md", "instructions.md", "output.schema.json"] {
                #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path))
            }
            let schema = try Data(contentsOf: directory.appendingPathComponent("output.schema.json"))
            #expect(try JSONSerialization.jsonObject(with: schema) is [String: Any])
        }
        """, to: tests.appendingPathComponent("DefinitionTests.swift"))
        try write("# \(id)\n\nIndependent Swift agent package. Version directories contain runtime definitions.\nOpen Package.swift in Xcode or run swift test in this directory.", to: package.appendingPathComponent("README.md"))
    }
    private static func write(_ text: String, to url: URL) throws { try (text + "\n").write(to: url, atomically: true, encoding: .utf8) }
}
