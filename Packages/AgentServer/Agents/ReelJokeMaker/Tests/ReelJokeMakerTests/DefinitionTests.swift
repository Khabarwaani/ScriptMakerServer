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

@Test func promptBuildingAndFeasibilityVerification() throws {
    let input = ReelJokeMakerInput(news: "City parks Wi-Fi router installed on a coconut tree in public park")
    let prompt = try ReelJokeMakerDefinition.buildPrompt(version: "1.0.0", input: input)
    #expect(prompt.contains("MASTER SYSTEM PROTOCOL"))
    #expect(prompt.contains("ROLE"))
    #expect(prompt.contains("INSTRUCTIONS"))
    #expect(prompt.contains("OUTPUT CONTRACT"))
    #expect(prompt.contains("CLIENT INPUT"))
    #expect(prompt.contains("coconut tree"))

    // Feasibility verification
    let validFeasibility = ReelJokeMakerDefinition.verifyFeasibility(input: input)
    #expect(validFeasibility == .feasible)

    let badInput = ReelJokeMakerInput(news: "short")
    let badFeasibility = ReelJokeMakerDefinition.verifyFeasibility(input: badInput)
    #expect(badFeasibility != .feasible)
    #expect(ReelJokeMakerDefinition.formatFailure(reason: "too short").contains("too short"))
}
