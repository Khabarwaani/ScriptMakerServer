import Testing
import Foundation
import NewsResearcher

@Test func definitionResourcesAreComplete() throws {
    for version in NewsResearcherDefinition.versions {
        let root = try NewsResearcherDefinition.directory(version: version)
        for name in ["role.md", "instructions.md", "output.schema.json", "input.schema.json"] {
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path))
        }
        let schema = try Data(contentsOf: root.appendingPathComponent("output.schema.json"))
        #expect(try JSONSerialization.jsonObject(with: schema) is [String: Any])
        #expect(try !NewsResearcherDefinition.role(version: version).isEmpty)
        #expect(try !NewsResearcherDefinition.instructions(version: version).isEmpty)
        #expect(try !NewsResearcherDefinition.outputSchema(version: version).isEmpty)
        #expect(try NewsResearcherDefinition.inputSchema(version: version) != nil)
    }
}

@Test func promptBuildingAndFeasibilityVerification() throws {
    let input = NewsResearcherInput(
        topic: "India semiconductor mission",
        language: "English",
        sourceURL: "https://isro.gov.in"
    )
    let prompt = try NewsResearcherDefinition.buildPrompt(version: "1.1.0", input: input)
    #expect(prompt.contains("MASTER SYSTEM PROTOCOL"))
    #expect(prompt.contains("ROLE"))
    #expect(prompt.contains("INSTRUCTIONS"))
    #expect(prompt.contains("OUTPUT CONTRACT"))
    #expect(prompt.contains("CLIENT INPUT"))

    let feasibility = NewsResearcherDefinition.verifyFeasibility(input: input)
    #expect(feasibility == .feasible)

    let emptyTopicInput = NewsResearcherInput(topic: "   ")
    let emptyFeasibility = NewsResearcherDefinition.verifyFeasibility(input: emptyTopicInput)
    #expect(emptyFeasibility != .feasible)

    let invalidUrlInput = NewsResearcherInput(topic: "Test topic", sourceURL: "ftp://invalid-url.com")
    let invalidUrlFeasibility = NewsResearcherDefinition.verifyFeasibility(input: invalidUrlInput)
    #expect(invalidUrlFeasibility != .feasible)
}
