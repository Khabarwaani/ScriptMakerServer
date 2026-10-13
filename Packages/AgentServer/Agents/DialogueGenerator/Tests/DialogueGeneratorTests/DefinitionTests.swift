import Foundation
import Testing
import DialogueGenerator

@Test func definitionResourcesAreComplete() throws {
    for version in DialogueGeneratorDefinition.versions {
        let root = try DialogueGeneratorDefinition.directory(version: version)
        for resource in ["role.md", "instructions.md", "input.schema.json", "output.schema.json"] {
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(resource).path))
        }
        #expect(try !DialogueGeneratorDefinition.role(version: version).isEmpty)
        #expect(try !DialogueGeneratorDefinition.instructions(version: version).isEmpty)
        #expect(try !DialogueGeneratorDefinition.outputSchema(version: version).isEmpty)
        #expect(try DialogueGeneratorDefinition.inputSchema(version: version) != nil)
    }
}
