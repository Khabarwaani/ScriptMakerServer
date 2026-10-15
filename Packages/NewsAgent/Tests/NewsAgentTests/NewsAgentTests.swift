import Testing
import Foundation
@testable import NewsAgent
import AgentAtom

struct NewsAgentTests {
    @Test
    func testSpecIdentityAndMetadata() {
        #expect(ShekharJokeGeneratorSpec.identity == Identity(
            id: "ShekharJokeGenerator",
            name: "Shekhar Joke Generator",
            version: "1.0.0"
        ))
        #expect(!ShekharJokeGeneratorSpec.role.isEmpty)
        #expect(!ShekharJokeGeneratorSpec.defaultInstructions.isEmpty)
    }

    @Test
    func testOutputSchemaDerivation() {
        let schema = ShekharJokeGeneratorSpec.outputSchema
        #expect(!schema.rawValue.isEmpty)
        #expect(schema.rawValue.contains("title"))
        #expect(schema.rawValue.contains("date"))
        #expect(schema.rawValue.contains("link"))
        #expect(schema.rawValue.contains("category"))
        #expect(schema.rawValue.contains("joke1"))
        #expect(schema.rawValue.contains("joke2"))
        #expect(schema.rawValue.contains("script"))
    }

    @Test
    func testInputSerialization() throws {
        let input = ShekharJokeGeneratorInput()
        let spec = ShekharJokeGeneratorSpec(input: input)
        let json = spec.inputJSON.rawValue
        #expect(json == "{}")
        let decoded = try JSONDecoder().decode(ShekharJokeGeneratorInput.self, from: Data(json.utf8))
        #expect(decoded == input)
    }

    @Test
    func testOutputRoundTripAndStorage() throws {
        var spec = ShekharJokeGeneratorSpec()
        #expect(spec.output == nil)

        let output = ShekharJokeGeneratorOutput(
            title: "ताज़ा खबर",
            date: "15-10-2026",
            link: "https://news.in/story",
            category: "Trending",
            joke1: "छोटा मज़ाक",
            joke2: "बड़ा मज़ाक",
            script: "#1\ntitle: ताज़ा खबर"
        )

        let encoded = try JSONEncoder().encode(output)
        let decoded = try JSONDecoder().decode(ShekharJokeGeneratorOutput.self, from: encoded)
        #expect(decoded == output)

        spec.output = decoded
        #expect(spec.output == output)
    }

    @Test
    func testCustomInstructions() {
        let custom = "Custom instructions for test"
        let spec = ShekharJokeGeneratorSpec(instructions: custom)
        #expect(spec.instructions == custom)
    }
}
