import Testing
import Foundation
import DialogueRefiner

@Test func definitionResourcesAreComplete() throws {
    for version in DialogueRefinerDefinition.versions {
        let root = try DialogueRefinerDefinition.directory(version: version)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("output.schema.json").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("role.md").path))
        #expect(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("instructions.md").path)
                || FileManager.default.fileExists(atPath: root.appendingPathComponent("instructions.1.md").path)
        )
        #expect(try !DialogueRefinerDefinition.role(version: version).isEmpty)
        #expect(try !DialogueRefinerDefinition.instructions(version: version).isEmpty)
        #expect(try !DialogueRefinerDefinition.outputSchema(version: version).isEmpty)
    }
}
