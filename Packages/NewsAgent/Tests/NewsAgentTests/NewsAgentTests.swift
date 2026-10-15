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
        #expect(schema.rawValue.contains("items"))
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
        #expect(json.contains(#""output_count":1"#))
        #expect(json.contains(#""news_count":3"#))
        #expect(json.contains(#""jokes_per_category":2"#))
        let decoded = try JSONDecoder().decode(ShekharJokeGeneratorInput.self, from: Data(json.utf8))
        #expect(decoded == input)

        let customInput = ShekharJokeGeneratorInput(outputCount: 2, newsCount: 5, jokesPerCategory: 3)
        let customEncoded = try JSONEncoder().encode(customInput)
        let customDecoded = try JSONDecoder().decode(ShekharJokeGeneratorInput.self, from: customEncoded)
        #expect(customDecoded.outputCount == 2)
        #expect(customDecoded.newsCount == 5)
        #expect(customDecoded.jokesPerCategory == 3)
    }

    @Test
    func testOutputRoundTripAndStorage() throws {
        var spec = ShekharJokeGeneratorSpec()
        #expect(spec.output == nil)

        let item = ShekharJokeItem(
            title: "ताज़ा खबर",
            date: "15-10-2026",
            link: "https://news.in/story",
            category: "Trending",
            joke1: "छोटा मज़ाक",
            joke2: "बड़ा मज़ाक",
            script: "#1\ntitle: ताज़ा खबर"
        )
        let output = ShekharJokeGeneratorOutput(items: [item])

        let encoded = try JSONEncoder().encode(output)
        let decoded = try JSONDecoder().decode(ShekharJokeGeneratorOutput.self, from: encoded)
        #expect(decoded == output)

        spec.output = decoded
        #expect(spec.output?.items.count == 1)
        #expect(spec.output?.items[0].title == "ताज़ा खबर")
    }

    @Test
    func testCustomInstructions() {
        let custom = "Custom instructions for test."
        let spec = ShekharJokeGeneratorSpec(instructions: custom)
        #expect(spec.instructions == custom)
    }
}
