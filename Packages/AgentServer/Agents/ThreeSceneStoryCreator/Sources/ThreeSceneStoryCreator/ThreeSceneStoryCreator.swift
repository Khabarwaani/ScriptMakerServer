import Foundation
import AgentCoreBase
@_exported import KhabarwaaniAgent

extension ThreeSceneStoryCreatorInput: @retroactive JSONSchemaConvertible {
    public static func schema() -> SchemaDefinition {
        SchemaDefinition(
            title: "ThreeSceneStoryCreatorInput",
            properties: [
                SchemaProperty(
                    name: "news",
                    type: "string",
                    description: "Verified news details, headline, or article facts.",
                    required: true
                ),
                SchemaProperty(
                    name: "user_joke",
                    type: "string",
                    description: "Optional user-provided joke or humorous angle to incorporate into Scene 3.",
                    required: false
                ),
                SchemaProperty(
                    name: "output_count",
                    type: "integer",
                    description: "Number of 3-scene story packages to generate. Defaults to 1.",
                    defaultValue: .number(1),
                    required: false,
                    minimum: 1,
                    maximum: 5
                )
            ],
            additionalProperties: false,
            examples: [
                .object([
                    "news": .string("Traffic department issues flying car fines")
                ]),
                .object([
                    "news": .string("Traffic department issues flying car fines"),
                    "user_joke": .string("Ab to chalan hawa me katega"),
                    "output_count": .number(1)
                ])
            ]
        )
    }
}

extension ThreeSceneStoryCreatorOutput: @retroactive JSONSchemaConvertible {
    public static func schema() -> SchemaDefinition {
        let sceneItemSchema = SchemaDefinition(
            title: "ThreeSceneItem",
            properties: [
                SchemaProperty(name: "purpose", type: "string", description: "Purpose/Focus of the scene.", required: true),
                SchemaProperty(name: "characters", type: "string", description: "Character name(s) or persona(s) appearing in this scene.", required: true),
                SchemaProperty(name: "setting", type: "string", description: "Setting/Environment where this scene occurs.", required: true),
                SchemaProperty(name: "speech", type: "string", description: "Spoken dialogue in natural running spoken flow (strictly 20 to 35 words).", required: true),
                SchemaProperty(name: "speech_word_count", type: "integer", description: "Exact word count of speech.", required: true),
                SchemaProperty(name: "joke_applied", type: "string", description: "Optional field showing the joke applied.", required: false)
            ],
            additionalProperties: false
        )

        let verificationSchema = SchemaDefinition(
            title: "ThreeSceneVerification",
            properties: [
                SchemaProperty(name: "different_concepts", type: "boolean", description: "True if Scene 1, 2, and 3 each hold completely different concepts.", required: true),
                SchemaProperty(name: "freshness_maintained", type: "boolean", description: "True if concept freshness and fresh faces are maintained across all three.", required: true),
                SchemaProperty(name: "shareability_verified", type: "boolean", description: "True if Scene 3 delivers strong fun/shareability.", required: true),
                SchemaProperty(name: "notes", type: "string", description: "Short summary of verification check.", required: true)
            ],
            additionalProperties: false
        )

        let packageSchema = SchemaDefinition(
            title: "ThreeSceneStoryPackage",
            properties: [
                SchemaProperty(name: "title", type: "string", description: "Catchy story title/headline.", required: true),
                SchemaProperty(name: "scene_1", type: "object", description: "Scene 1: Creating Curiosity (20 to 35 words).", required: true, nestedSchema: sceneItemSchema),
                SchemaProperty(name: "scene_2", type: "object", description: "Scene 2: News Getting Discussed (20 to 35 words).", required: true, nestedSchema: sceneItemSchema),
                SchemaProperty(name: "scene_3", type: "object", description: "Scene 3: Fun & Shareable Reaction (20 to 35 words).", required: true, nestedSchema: sceneItemSchema),
                SchemaProperty(name: "verification", type: "object", description: "Mandatory internal verification step before final output.", required: true, nestedSchema: verificationSchema)
            ],
            additionalProperties: false
        )

        return SchemaDefinition(
            title: "ThreeSceneStoryCreatorOutput",
            properties: [
                SchemaProperty(
                    name: "items",
                    type: "array",
                    description: "Array of generated 3-scene story packages matching requested output_count.",
                    required: true,
                    itemsSchema: packageSchema,
                    minItems: 1,
                    maxItems: 5
                )
            ],
            additionalProperties: false
        )
    }
}

/// Provider-independent, versioned ThreeSceneStoryCreator agent definition conforming to AgentProtocol.
public enum ThreeSceneStoryCreatorDefinition: AgentProtocol, FailureRecoverableAgent {
    public typealias Input = ThreeSceneStoryCreatorInput
    public typealias Output = ThreeSceneStoryCreatorOutput

    public static let id = ThreeSceneStoryCreatorSpec.identity.id
    public static let name = ThreeSceneStoryCreatorSpec.identity.name
    public static let versions: [String] = [ThreeSceneStoryCreatorSpec.identity.version]
    public static var bundle: Bundle { Bundle.module }

    public static func verifyFeasibility(input: ThreeSceneStoryCreatorInput) -> FeasibilityResult {
        guard !input.news.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .unfeasible(reason: "news must not be empty")
        }
        guard input.outputCount >= 1 && input.outputCount <= 5 else {
            return .unfeasible(reason: "output_count must be between 1 and 5")
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
