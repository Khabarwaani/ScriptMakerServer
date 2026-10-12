import AgentCore
import Foundation

@main
struct AgentTools {
    static func main() async {
        do { try await run() } catch {
            print("AgentTools: \(error)")
            exit(1)
        }
    }
    private static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let configuration = try ServerConfiguration(workingDirectory: packageRoot)
        switch args.first {
        case "add" where args.count == 2 || args.count == 3:
            try AgentPackageTools.create(
                id: args[1], version: args.count == 3 ? args[2] : "1.0.0", root: configuration.agentsDirectory
            )
            print(
                "Created Swift agent package \(args[1]). Edit its role, instructions and schemas before publication."
            )
        case "version" where args.count == 4:
            try AgentPackageTools.addVersion(
                id: args[1], version: args[2], sourceVersion: args[3], root: configuration.agentsDirectory)
            print("Created new version \(args[2]) from \(args[3]).")
        case "check" where args.count == 1 || args == ["check", "--build"]:
            let issues = try AgentPackageTools.check(root: configuration.agentsDirectory)
            guard issues.isEmpty else {
                print(issues.joined(separator: "\n"))
                exit(1)
            }
            print("All Swift agent package files and schemas are valid.")
            if args.contains("--build") {
                let packages = try FileManager.default.contentsOfDirectory(
                    at: configuration.agentsDirectory, includingPropertiesForKeys: [.isDirectoryKey]
                ).filter {
                    FileManager.default.fileExists(atPath: $0.appendingPathComponent("Package.swift").path)
                }
                for package in packages {
                    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(
                        "AgentPackageChecks/\(package.lastPathComponent)")
                    let result = try await ProcessRunner().run(
                        executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                        arguments: [
                            "swift", "test", "--package-path", package.path, "--scratch-path", scratch.path,
                        ], timeoutSeconds: 300)
                    print(result)
                }
            }
        case "docs" where args.count == 1 || args == ["docs", "--check"]:
            let checkOnly = args.contains("--check")
            let changed = try AgentDocumentationGenerator.synchronizeReadmes(
                in: configuration.agentsDirectory, checkOnly: checkOnly)
            if checkOnly && !changed.isEmpty {
                print(changed.map { "\($0): README.md is out of date. Run AgentTools docs." }.joined(separator: "\n"))
                exit(1)
            }
            print(checkOnly ? "All package READMEs match their versioned resources." : "Updated \(changed.count) package README(s).")
        default:
            print(
                "Usage: swift run AgentTools add AGENT [VERSION]\n       swift run AgentTools version AGENT NEW_VERSION SOURCE_VERSION\n       swift run AgentTools check [--build]\n       swift run AgentTools docs [--check]"
            )
            exit(2)
        }
    }
}
