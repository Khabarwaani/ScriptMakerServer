import Foundation
import Testing
import ReelIdeaGenerator

@Test func definitionResourcesAreComplete() throws {
    for version in ReelIdeaGeneratorDefinition.versions {
        let root = try ReelIdeaGeneratorDefinition.directory(version: version)
        for resource in ["role.md", "instructions.md", "input.schema.json", "output.schema.json"] {
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(resource).path))
        }
        #expect(try !ReelIdeaGeneratorDefinition.role(version: version).isEmpty)
        #expect(try !ReelIdeaGeneratorDefinition.instructions(version: version).isEmpty)
        #expect(try !ReelIdeaGeneratorDefinition.outputSchema(version: version).isEmpty)
        #expect(try ReelIdeaGeneratorDefinition.inputSchema(version: version) != nil)
    }
}
