import Testing
import Foundation
import ReelJokeMaker

@Test func definitionResourcesAreComplete() throws {
    for version in ReelJokeMakerDefinition.versions {
        let root = try ReelJokeMakerDefinition.directory(version: version)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("output.schema.json").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("role.md").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("instructions.md").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("input.schema.json").path))

        #expect(try !ReelJokeMakerDefinition.role(version: version).isEmpty)
        #expect(try !ReelJokeMakerDefinition.instructions(version: version).isEmpty)
        #expect(try !ReelJokeMakerDefinition.outputSchema(version: version).isEmpty)
        #expect(try ReelJokeMakerDefinition.inputSchema(version: version) != nil)
    }
}
