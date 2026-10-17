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
        let dialogueSchema = SchemaDefinition(
            title: "ThreeSceneDialogue",
            properties: [
                SchemaProperty(name: "speaker", type: "string", description: "Name or persona of speaking character.", required: true),
                SchemaProperty(name: "dialogue", type: "string", description: "Spoken line in natural reply-response flow.", required: true)
            ],
            additionalProperties: false
        )

        let verificationSchema = SchemaDefinition(
            title: "ThreeSceneVerification",
            properties: [
                SchemaProperty(name: "passed", type: "boolean", description: "True if all verification checks passed.", required: true),
                SchemaProperty(name: "dialogue_sensible", type: "boolean", description: "True if dialogue makes complete sense, is meaningful, and has natural reply-response flow.", required: true),
                SchemaProperty(name: "different_concepts", type: "boolean", description: "True if this scene holds a distinct concept.", required: true),
                SchemaProperty(name: "freshness_maintained", type: "boolean", description: "True if fresh faces, fresh setting, and no recycled setups are maintained.", required: true),
                SchemaProperty(name: "notes", type: "string", description: "Short summary of verification check.", required: true)
            ],
            additionalProperties: false
        )

        let sceneItemSchema = SchemaDefinition(
            title: "ThreeSceneItem",
            properties: [
                SchemaProperty(name: "title", type: "string", description: "Scene title.", required: true),
                SchemaProperty(name: "goal", type: "string", description: "Goal/Purpose of the scene (Curiosity / News Discussion / Shareable Reaction).", required: true),
                SchemaProperty(name: "location", type: "string", description: "Setting or environment where this scene occurs.", required: true),
                SchemaProperty(name: "verification", type: "object", description: "Internal verification record for this scene.", required: true, nestedSchema: verificationSchema),
                SchemaProperty(name: "dialogues", type: "array", description: "List of natural reply-response dialogue turns between characters.", required: true, itemsSchema: dialogueSchema),
                SchemaProperty(name: "words_count", type: "integer", description: "Total count of spoken words across all dialogues, calculated last (strictly 20 to 35 words).", required: true, minimum: 20, maximum: 35)
            ],
            additionalProperties: false
        )

        let packageSchema = SchemaDefinition(
            title: "ThreeSceneStoryPackage",
            properties: [
                SchemaProperty(name: "title", type: "string", description: "Catchy story title/headline.", required: true),
                SchemaProperty(name: "scenes", type: "array", description: "Array of 3 Scene objects (Curiosity, News Discussion, Shareable Reaction).", required: true, itemsSchema: sceneItemSchema, minItems: 3, maxItems: 3)
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
