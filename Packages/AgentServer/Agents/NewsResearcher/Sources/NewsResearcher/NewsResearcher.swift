import Foundation
import AgentCoreBase
@_exported import KhabarwaaniAgent

extension NewsResearcherInput: @retroactive JSONSchemaConvertible {
    public static func schema() -> SchemaDefinition {
        SchemaDefinition(
            title: "NewsResearcherInput",
            properties: [
                SchemaProperty(
                    name: "topic",
                    type: "string",
                    description: "Research topic",
                    required: true
                ),
                SchemaProperty(
                    name: "language",
                    type: "string",
                    description: "Language for findings",
                    defaultValue: .string("English"),
                    required: false
                ),
                SchemaProperty(
                    name: "source_url",
                    type: "string",
                    description: "Optional authoritative source to use for the entire run",
                    required: false
                )
            ],
            additionalProperties: false,
            examples: [
                .object([
                    "topic": .string("India's semiconductor industry"),
                    "language": .string("English")
                ])
            ]
        )
    }
}

extension NewsResearcherOutput: @retroactive JSONSchemaConvertible {
    public static func schema() -> SchemaDefinition {
        let locationSchema = SchemaDefinition(
            title: "NewsLocation",
            properties: [
                SchemaProperty(name: "city", type: "string", required: false),
                SchemaProperty(name: "state", type: "string", required: false),
                SchemaProperty(name: "country", type: "string", required: false)
            ],
            additionalProperties: false
        )

        return SchemaDefinition(
            title: "NewsResearcherOutput",
            properties: [
                SchemaProperty(name: "verified", type: "boolean", description: "Whether the news was verified.", required: true),
                SchemaProperty(name: "confidence", type: "integer", description: "Confidence score 0-100.", required: true, minimum: 0, maximum: 100),
                SchemaProperty(name: "date", type: "string", description: "dd-mm-yy", required: true),
                SchemaProperty(name: "location", type: "object", description: "Location of the event.", required: false, nestedSchema: locationSchema),
                SchemaProperty(name: "people", type: "array", description: "People involved.", required: false, itemsSchema: SchemaDefinition(properties: [SchemaProperty(name: "person", type: "string")])),
                SchemaProperty(name: "notes", type: "array", description: "1-3 points, 5-15 words each", required: false, itemsSchema: SchemaDefinition(properties: [SchemaProperty(name: "note", type: "string")]), minItems: 1, maxItems: 3),
                SchemaProperty(name: "hashtags", type: "array", description: "Max 5 hashtags", required: false, itemsSchema: SchemaDefinition(properties: [SchemaProperty(name: "hashtag", type: "string")]), maxItems: 5)
            ],
            additionalProperties: false
        )
    }
}

/// Provider-independent, versioned NewsResearcher agent definition conforming to AgentProtocol.
public enum NewsResearcherDefinition: AgentProtocol, FailureRecoverableAgent {
    public typealias Input = NewsResearcherInput
    public typealias Output = NewsResearcherOutput

    public static let id = NewsResearcherSpec.identity.id
    public static var name: String {
        KhabarwaaniAgent.agents[id]?.name ?? NewsResearcherSpec.identity.name
    }
    public static var versions: [String] {
        if let descriptor = KhabarwaaniAgent.agents[id] {
            return [descriptor.latestVersion]
        }
        return [NewsResearcherSpec.identity.version]
    }
    public static var bundle: Bundle { Bundle.module }

    public static func verifyFeasibility(input: NewsResearcherInput) -> FeasibilityResult {
        let trimmed = input.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .unfeasible(reason: "topic must not be empty")
        }
        if let source = input.sourceURL, !source.isEmpty {
            guard source.hasPrefix("http://") || source.hasPrefix("https://") else {
                return .unfeasible(reason: "source_url must start with http:// or https://")
            }
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
