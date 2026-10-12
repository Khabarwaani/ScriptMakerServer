import PackagePlugin
import Foundation

@main
struct ValidateAgentsPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }

        let validatorTool = try context.tool(named: "AgentValidator")
        let packageDir = context.package.directoryURL
        let agentsDir = packageDir.appendingPathComponent("Agents")

        let workDir = context.pluginWorkDirectoryURL
        let outputJSON = workDir.appendingPathComponent("agent-validation.json")
        let outputSwift = workDir.appendingPathComponent("GeneratedAgentValidationCatalog.swift")

        // Find all input files in Agents to track changes
        var inputFiles: [URL] = []
        let fileManager = FileManager.default
        func collectFiles(in dir: URL) {
            guard let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey]) else { return }
            for item in contents {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDir) {
                    if isDir.boolValue {
                        collectFiles(in: item)
                    } else {
                        let ext = item.pathExtension
                        if ["swift", "json", "md"].contains(ext) {
                            inputFiles.append(item)
                        }
                    }
                }
            }
        }
        collectFiles(in: agentsDir)

        return [
            .buildCommand(
                displayName: "Validating agent definitions and contracts",
                executable: validatorTool.url,
                arguments: [
                    agentsDir.path,
                    outputJSON.path,
                    outputSwift.path
                ],
                inputFiles: inputFiles,
                outputFiles: [outputJSON, outputSwift]
            )
        ]
    }
}
