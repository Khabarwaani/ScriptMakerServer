import Foundation
import AgentCoreBase
@_exported import NewsAgent

extension ShekharJokeGeneratorInput: @retroactive JSONSchemaConvertible {
    public static func schema() -> SchemaDefinition {
        SchemaDefinition(
            title: "ShekharJokeGeneratorInput",
            properties: [
                SchemaProperty(name: "topic", type: "string", description: "Optional news topic or focus area to guide news selection."),
                SchemaProperty(name: "news_source_url", type: "string", description: "Optional direct news article URL to include in curation.")
            ],
            additionalProperties: false,
            examples: [
                .object([:])
            ]
        )
    }
}

extension ShekharJokeGeneratorOutput: @retroactive JSONSchemaConvertible {
    public static func schema() -> SchemaDefinition {
        SchemaDefinition(
            title: "ShekharJokeGeneratorOutput",
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
    }
}

/// Provider-independent, versioned ShekharJokeGenerator agent definition conforming to AgentProtocol.
public enum ShekharJokeGeneratorDefinition: AgentProtocol, FailureRecoverableAgent {
    public typealias Input = ShekharJokeGeneratorInput
    public typealias Output = ShekharJokeGeneratorOutput

    public static let id = ShekharJokeGeneratorSpec.identity.id
    public static let name = ShekharJokeGeneratorSpec.identity.name
    public static let versions: [String] = [ShekharJokeGeneratorSpec.identity.version]
    public static var bundle: Bundle { Bundle.module }

    public static func verifyFeasibility(input: ShekharJokeGeneratorInput) -> FeasibilityResult {
        .feasible
    }

    public static func formatFailure(reason: String) -> String {
        "{\"error\":{\"reason\":\"\(reason)\"}}"
    }

    public enum DefinitionError: Error, Sendable, Equatable {
        case unknownVersion
    }
}
