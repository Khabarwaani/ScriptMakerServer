import Foundation
import AgentCoreBase

/// Typed input payload for ShekharJokeGenerator.
public struct ShekharJokeGeneratorInput: Codable, Sendable, Equatable, JSONSchemaConvertible {
    /// Optional topic or focus area to guide news selection.
    public var topic: String?
    /// Optional direct news source URL.
    public var newsSourceURL: String?

    public init(topic: String? = nil, newsSourceURL: String? = nil) {
        self.topic = topic
        self.newsSourceURL = newsSourceURL
    }

    enum CodingKeys: String, CodingKey {
        case topic
        case newsSourceURL = "news_source_url"
    }

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

/// Typed output payload for ShekharJokeGenerator.
public struct ShekharJokeGeneratorOutput: Codable, Sendable, Equatable, JSONSchemaConvertible {
    /// Winning news headline in Hindi.
    public var title: String
    /// Verified publication date and time.
    public var date: String
    /// Direct article URL.
    public var link: String
    /// Selection category of the winning news story ("Trending", "Meme Potential", or "Public Importance").
    public var category: String
    /// Winning story's short Hindi joke, maximum 30 words in Devanagari Hindi.
    public var joke1: String
    /// Winning story's long Hindi joke, maximum 60 words in Devanagari Hindi.
    public var joke2: String
    /// Formatted plain-text script ready for direct display or broadcast.
    public var script: String

    public init(
        title: String,
        date: String,
        link: String,
        category: String,
        joke1: String,
        joke2: String,
        script: String
    ) {
        self.title = title
        self.date = date
        self.link = link
        self.category = category
        self.joke1 = joke1
        self.joke2 = joke2
        self.script = script
    }

    enum CodingKeys: String, CodingKey {
        case title
        case date
        case link
        case category
        case joke1
        case joke2
        case script
    }

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

    public static let id = "ShekharJokeGenerator"
    public static let name = "Shekhar Joke Generator"
    public static let versions: [String] = ["1.0.0"]
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
