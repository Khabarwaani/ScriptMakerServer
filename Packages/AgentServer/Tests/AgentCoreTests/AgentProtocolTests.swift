import Foundation
import Testing
import ReelJokeMaker
import ThreeSceneStoryCreator

@testable import AgentCore

@Test func schemaBuilderGeneratesDraft202012CompliantSchema() throws {
    let schema = SchemaDefinition(
        title: "TestSchema",
        description: "A test schema definition",
        properties: [
            SchemaProperty(name: "message", type: "string", description: "A string message", required: true),
            SchemaProperty(name: "count", type: "integer", defaultValue: .number(5), minimum: 1, maximum: 10),
            SchemaProperty(name: "ratio", type: "number", defaultValue: .number(2.5)),
            SchemaProperty(name: "tags", type: "array", itemsSchema: SchemaDefinition(properties: [SchemaProperty(name: "tag", type: "string")]))
        ],
        additionalProperties: false
    )

    let jsonValue = schema.toJSONValue()
    #expect(jsonValue["$schema"] == .string("https://json-schema.org/draft/2020-12/schema"))
    #expect(jsonValue["type"] == .string("object"))
    #expect(jsonValue["additionalProperties"] == .bool(false))
    #expect(jsonValue["required"] == .array([.string("message")]))
    #expect(jsonValue["properties"]?["count"]?["default"] == .number(5))

    // Must satisfy OutputValidator.checkSchema without throwing
    try OutputValidator.checkSchema(jsonValue)
}

private struct MockInput: Codable, Sendable, JSONSchemaConvertible {
    var prompt: String
    var count: Int

    static func schema() -> SchemaDefinition {
        SchemaDefinition(
            title: "MockInput",
            properties: [
                SchemaProperty(name: "prompt", type: "string", required: true),
                SchemaProperty(name: "count", type: "integer", defaultValue: .number(1), minimum: 1)
            ],
            additionalProperties: false
        )
    }
}

private struct MockOutput: Codable, Sendable, JSONSchemaConvertible {
    var result: String

    static func schema() -> SchemaDefinition {
        SchemaDefinition(
            title: "MockOutput",
            properties: [
                SchemaProperty(name: "result", type: "string", required: true)
            ],
            additionalProperties: false
        )
    }
}

private enum MockAgent: AgentProtocol {
    typealias Input = MockInput
    typealias Output = MockOutput

    static let id = "MockAgent"
    static let versions = ["1.0.0"]
    static var bundle: Bundle { Bundle.main }

    static func directory(version: String) throws -> URL {
        URL(fileURLWithPath: "/tmp/mock")
    }
}

@Test func agentProtocolSynthesizesSchemasFromConvertibleTypes() throws {
    let outSchemaStr = try MockAgent.outputSchema(version: "1.0.0")
    let outJSON = try JSONValue.parse(outSchemaStr)
    try OutputValidator.checkSchema(outJSON)
    #expect(outJSON["properties"]?["result"]?["type"] == .string("string"))

    let inSchemaStr = try MockAgent.inputSchema(version: "1.0.0")
    #expect(inSchemaStr != nil)
    let inJSON = try JSONValue.parse(inSchemaStr!)
    try OutputValidator.checkSchema(inJSON)
    #expect(inJSON["properties"]?["prompt"]?["type"] == .string("string"))
}

@Test func reelJokeMakerRegisteredAndResolvesInRegistry() async throws {
    let registry = AgentRegistry()
    let agents = await registry.availableAgents()
    #expect(agents.contains(where: { $0.id == "ReelJokeMaker" }))

    let definition = try await registry.resolve(id: "ReelJokeMaker", version: "1.0.0")
    #expect(definition.id == "ReelJokeMaker")
    #expect(definition.version == "1.0.0")
    #expect(!definition.role.isEmpty)
    #expect(!definition.instructions.isEmpty)
    #expect(definition.inputSchema != nil)
    #expect(definition.outputSchema["properties"]?["key_facts"] != nil)
    #expect(definition.outputSchema["properties"]?["characters"] != nil)
    #expect(definition.outputSchema["properties"]?["variations"] != nil)
}

@Test func reelJokeMakerModelsCodableRoundTrip() throws {
    let input = ReelJokeMakerInput(
        news: "City parks Wi-Fi router on coconut tree",
        language: "hi-IN",
        durationSeconds: 10.0,
        wpsRange: ReelWpsRange(min: 2.5, max: 3.5),
        outputCount: 3
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(input)
    let decoded = try JSONDecoder().decode(ReelJokeMakerInput.self, from: data)
    #expect(decoded == input)

    let variation = ReelJokeVariation(
        variationIndex: 1,
        hook: "Free Wi-Fi! 🌴",
        dialogues: [
            ReelDialogue(speaker: "A", text: "Wi-Fi kahan hai?", deliveryEmotion: "Shocked", spokenDurationSeconds: 2.0, pauseAfterSeconds: 0.5),
            ReelDialogue(speaker: "B", text: "Nariyal ke ped pe!", deliveryEmotion: "Sarcastic", spokenDurationSeconds: 2.5, pauseAfterSeconds: 0.5)
        ],
        scenes: [
            ReelScene(sceneNumber: 1, location: "Park", characterActions: "Looking up", popoverText: "Signal 0%", durationSeconds: 5.5)
        ],
        humorNotes: "Satirical municipal joke",
        totalDurationSeconds: 5.5
    )

    let output = ReelJokeMakerOutput(
        keyFacts: ["Park Wi-Fi", "Router on coconut tree"],
        characters: [
            ReelCharacter(name: "A", roleDescription: "Student", clothingAndLook: "Jeans", voiceTone: "Confused")
        ],
        variations: [variation]
    )

    let outData = try encoder.encode(output)
    let decodedOut = try JSONDecoder().decode(ReelJokeMakerOutput.self, from: outData)
    #expect(decodedOut == output)
}

@Test(arguments: [false, true])
func allAgentVersionsReceiveGlobalClarityGuidance(nativeEnvelope: Bool) async throws {
    let registry = AgentRegistry()
    let agents = await registry.availableAgents()
    #expect(agents.count > 1)
    for agent in agents {
        for version in agent.versions {
            let definition = try await registry.resolve(id: agent.id, version: version)
            let prompt = try CLIProvider.prompt(
                definition: definition, input: .object([:]), nativeEnvelope: nativeEnvelope)
            #expect(prompt.components(separatedBy: GenerationGuidance.clarity).count == 2)
            #expect(prompt.contains(definition.instructions))
            #expect(prompt.contains("OUTPUT CONTRACT"))
        }
    }
}

@Test func typedAgentPromptUsesTheSameGlobalClarityGuidance() throws {
    let input = ReelJokeMakerInput(
        news: "City opens a new park", language: "hi-IN", durationSeconds: 10,
        wpsRange: ReelWpsRange(min: 2.5, max: 3.5), outputCount: 3)
    let prompt = try ReelJokeMakerDefinition.buildPrompt(version: "1.0.0", input: input)
    #expect(prompt.components(separatedBy: GenerationGuidance.clarity).count == 2)
    #expect(prompt.contains("City opens a new park"))
    #expect(prompt.contains("OUTPUT CONTRACT"))
}

@Test func threeSceneStoryCreatorPromptUsesGlobalClarityGuidance() throws {
    let input = ThreeSceneStoryCreatorInput(
        news: "Traffic police introduces drone fines",
        userJoke: "Chalan seedha chat pe aayega",
        outputCount: 1
    )
    let prompt = try ThreeSceneStoryCreatorDefinition.buildPrompt(version: "2.0.0", input: input)
    #expect(prompt.components(separatedBy: GenerationGuidance.clarity).count == 2)
    #expect(prompt.contains("Traffic police introduces drone fines"))
    #expect(prompt.contains("Chalan seedha chat pe aayega"))
    #expect(prompt.contains("OUTPUT CONTRACT"))
}

