import Foundation
import AgentCoreBase
@_exported import KhabarwaaniAgent

extension ShekharJokeGeneratorInput: @retroactive JSONSchemaConvertible {
    public static func schema() -> SchemaDefinition {
        SchemaDefinition(
            title: "ShekharJokeGeneratorInput",
            properties: [
                SchemaProperty(
                    name: "output_count",
                    type: "integer",
                    description: "Number of winning news story joke packages to return in the items output array. Defaults to 1.",
                    defaultValue: .number(1),
                    required: false,
                    minimum: 1,
                    maximum: 5
                ),
                SchemaProperty(
                    name: "news_count",
                    type: "integer",
                    description: "Number of verified Indian news stories to research and evaluate. Defaults to 3.",
                    defaultValue: .number(3),
                    required: false,
                    minimum: 1,
                    maximum: 10
                ),
                SchemaProperty(
                    name: "jokes_per_category",
                    type: "integer",
                    description: "Number of joke variations (e.g. short, long) to generate and evaluate for each story category. Defaults to 2.",
                    defaultValue: .number(2),
                    required: false,
                    minimum: 1,
                    maximum: 5
                )
            ],
            additionalProperties: false,
            examples: [
                .object([:]),
                .object([
                    "output_count": .number(1),
                    "news_count": .number(3),
                    "jokes_per_category": .number(2)
                ])
            ]
        )
    }
}

extension ShekharJokeGeneratorOutput: @retroactive JSONSchemaConvertible {
    public static func schema() -> SchemaDefinition {
        let itemSchema = SchemaDefinition(
            title: "ShekharJokeItem",
            properties: [
                SchemaProperty(name: "title", type: "string", description: "Winning news headline in Hindi.", required: true),
                SchemaProperty(name: "date", type: "string", description: "Verified publication date and time.", required: true),
                SchemaProperty(name: "link", type: "string", description: "Direct article URL.", required: true),
                SchemaProperty(name: "category", type: "string", description: "Selection category of the winning news story.", required: true, enumValues: ["Trending", "Meme Potential", "Public Importance"]),
                SchemaProperty(name: "joke1", type: "string", description: "Winning story's short Hindi joke, maximum 30 words in Devanagari Hindi.", required: true),
                SchemaProperty(name: "joke2", type: "string", description: "Winning story's long Hindi joke, maximum 60 words in Devanagari Hindi.", required: true),
                SchemaProperty(name: "script", type: "string", description: "Clean, formatted plain-text script ready for direct display or broadcast.", required: true)
            ],
            additionalProperties: false
        )

        return SchemaDefinition(
            title: "ShekharJokeGeneratorOutput",
            properties: [
                SchemaProperty(
                    name: "items",
                    type: "array",
                    description: "Array of winning news story joke packages matching the requested output_count.",
                    required: true,
                    itemsSchema: itemSchema,
                    minItems: 1,
                    maxItems: 5
                )
            ],
            additionalProperties: false
        )
    }
}

/// Provider-independent, versioned ShekharJokeGenerator agent definition conforming to AgentProtocol.
public enum ShekharJokeGeneratorDefinition: AgentProtocol, FailureRecoverableAgent {
    public typealias Input = ShekharJokeGeneratorInput
    public typealias Output = ShekharJokeGeneratorOutput

    public static let id = ShekharJokeGeneratorSpec.identity.id
    public static var name: String {
        KhabarwaaniAgent.agents[id]?.name ?? ShekharJokeGeneratorSpec.identity.name
    }
    public static var versions: [String] {
        if let descriptor = KhabarwaaniAgent.agents[id] {
            return [descriptor.latestVersion]
        }
        return [ShekharJokeGeneratorSpec.identity.version]
    }
    public static var bundle: Bundle { Bundle.module }

    public static func verifyFeasibility(input: ShekharJokeGeneratorInput) -> FeasibilityResult {
        guard input.outputCount >= 1 && input.outputCount <= 5 else {
            return .unfeasible(reason: "output_count must be between 1 and 5")
        }
        guard input.newsCount >= 1 && input.newsCount <= 10 else {
            return .unfeasible(reason: "news_count must be between 1 and 10")
        }
        guard input.jokesPerCategory >= 1 && input.jokesPerCategory <= 5 else {
            return .unfeasible(reason: "jokes_per_category must be between 1 and 5")
        }
        return .feasible
    }

    public static func formatFailure(reason: String) -> String {
        "{\"error\":{\"reason\":\"\(reason)\"}}"
    }

    public enum DefinitionError: Error, Sendable, Equatable {
        case unknownVersion
    }
}
