import Foundation
import Testing
import ThemeMixer

@Test func definitionResourcesAreComplete() throws {
    for version in ThemeMixerDefinition.versions {
        let root = try ThemeMixerDefinition.directory(version: version)
        for resource in ["role.md", "instructions.md", "input.schema.json", "output.schema.json"] {
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(resource).path))
        }
        #expect(try !ThemeMixerDefinition.role(version: version).isEmpty)
        #expect(try !ThemeMixerDefinition.instructions(version: version).isEmpty)
        #expect(try !ThemeMixerDefinition.outputSchema(version: version).isEmpty)
        #expect(try ThemeMixerDefinition.inputSchema(version: version) != nil)
    }
}
