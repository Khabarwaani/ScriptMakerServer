import Testing
import Foundation
import ScriptRefiner

@Test func definitionResourcesAreComplete() throws {
    for version in ScriptRefinerDefinition.versions {
        let root = try ScriptRefinerDefinition.directory(version: version)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("output.schema.json").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("role.md").path))
        #expect(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("instructions.md").path)
                || FileManager.default.fileExists(atPath: root.appendingPathComponent("instructions.1.md").path)
        )
        #expect(try !ScriptRefinerDefinition.role(version: version).isEmpty)
        #expect(try !ScriptRefinerDefinition.instructions(version: version).isEmpty)
        #expect(try !ScriptRefinerDefinition.outputSchema(version: version).isEmpty)
    }
}
