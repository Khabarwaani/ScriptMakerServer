import Testing
import Foundation
import ShekharJokeGenerator

@Test func definitionResourcesAreComplete() throws {
    for version in ShekharJokeGeneratorDefinition.versions {
        let root = try ShekharJokeGeneratorDefinition.directory(version: version)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("output.schema.json").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("role.md").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("instructions.md").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("input.schema.json").path))

        #expect(try !ShekharJokeGeneratorDefinition.role(version: version).isEmpty)
        #expect(try !ShekharJokeGeneratorDefinition.instructions(version: version).isEmpty)
        #expect(try !ShekharJokeGeneratorDefinition.outputSchema(version: version).isEmpty)
        #expect(try ShekharJokeGeneratorDefinition.inputSchema(version: version) != nil)
    }
}

@Test func promptBuildingAndFeasibilityVerification() throws {
    let input = ShekharJokeGeneratorInput()
    let prompt = try ShekharJokeGeneratorDefinition.buildPrompt(version: "1.0.0", input: input)
    #expect(prompt.contains("MASTER SYSTEM PROTOCOL"))
    #expect(prompt.contains("ROLE"))
    #expect(prompt.contains("INSTRUCTIONS"))
    #expect(prompt.contains("OUTPUT CONTRACT"))
    #expect(prompt.contains("CLIENT INPUT"))

    let feasibility = ShekharJokeGeneratorDefinition.verifyFeasibility(input: input)
    #expect(feasibility == .feasible)
}
