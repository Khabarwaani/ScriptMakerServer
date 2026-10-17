import Testing
import Foundation
import ThreeSceneStoryCreator

@Test func definitionResourcesAreComplete() throws {
    for version in ThreeSceneStoryCreatorDefinition.versions {
        let root = try ThreeSceneStoryCreatorDefinition.directory(version: version)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("output.schema.json").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("role.md").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("instructions.md").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("input.schema.json").path))

        #expect(try !ThreeSceneStoryCreatorDefinition.role(version: version).isEmpty)
        #expect(try !ThreeSceneStoryCreatorDefinition.instructions(version: version).isEmpty)
        #expect(try !ThreeSceneStoryCreatorDefinition.outputSchema(version: version).isEmpty)
        #expect(try ThreeSceneStoryCreatorDefinition.inputSchema(version: version) != nil)
    }
}

@Test func promptBuildingAndFeasibilityVerification() throws {
    let input = ThreeSceneStoryCreatorInput(
        news: "Traffic department issues flying car fines",
        userJoke: "Ab to chalan hawa me katega"
    )
    let prompt = try ThreeSceneStoryCreatorDefinition.buildPrompt(version: "1.0.0", input: input)
    #expect(prompt.contains("MASTER SYSTEM PROTOCOL"))
    #expect(prompt.contains("ROLE"))
    #expect(prompt.contains("INSTRUCTIONS"))
    #expect(prompt.contains("OUTPUT CONTRACT"))
    #expect(prompt.contains("CLIENT INPUT"))

    let feasibility = ThreeSceneStoryCreatorDefinition.verifyFeasibility(input: input)
    #expect(feasibility == .feasible)

    let emptyNewsInput = ThreeSceneStoryCreatorInput(news: "   ")
    let emptyFeasibility = ThreeSceneStoryCreatorDefinition.verifyFeasibility(input: emptyNewsInput)
    #expect(emptyFeasibility != .feasible)
}
