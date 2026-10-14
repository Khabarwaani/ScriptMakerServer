import Foundation
import AgentCoreBase

/// Pacing range governing dialogue speech pacing in words per second.
public struct ReelWpsRange: Codable, Sendable, Equatable, JSONSchemaConvertible {
    public var min: Double
    public var max: Double

    public init(min: Double = 2.5, max: Double = 3.5) {
        self.min = min
        self.max = max
    }

    public static func schema() -> SchemaDefinition {
        SchemaDefinition(
            title: "wps_range",
            description: "Target words-per-second (WPS) pacing range governing dialogue timing.",
            properties: [
                SchemaProperty(name: "min", type: "number", description: "Minimum words per second for spoken dialogue.", defaultValue: .number(2.5), required: true, minimum: 0),
                SchemaProperty(name: "max", type: "number", description: "Maximum words per second for spoken dialogue.", defaultValue: .number(3.5), required: true, minimum: 0)
            ],
            additionalProperties: false
        )
    }
}

/// Character profile with visual details and clothing for vertical mobile framing.
public struct ReelCharacter: Codable, Sendable, Equatable, JSONSchemaConvertible {
    public var name: String
    public var roleDescription: String
    public var clothingAndLook: String
    public var voiceTone: String

    public init(name: String, roleDescription: String, clothingAndLook: String, voiceTone: String) {
        self.name = name
        self.roleDescription = roleDescription
        self.clothingAndLook = clothingAndLook
        self.voiceTone = voiceTone
    }

    enum CodingKeys: String, CodingKey {
        case name
        case roleDescription = "role_description"
        case clothingAndLook = "clothing_and_look"
        case voiceTone = "voice_tone"
    }

    public static func schema() -> SchemaDefinition {
        SchemaDefinition(
            title: "character",
            properties: [
                SchemaProperty(name: "name", type: "string", description: "Character name.", required: true),
                SchemaProperty(name: "role_description", type: "string", description: "Character comedic archetype.", required: true),
                SchemaProperty(name: "clothing_and_look", type: "string", description: "Visual appearance, grooming, and clothing details suited for 9:16 vertical framing.", required: true),
                SchemaProperty(name: "voice_tone", type: "string", description: "Distinct voice tone and delivery attitude.", required: true)
            ],
            additionalProperties: false
        )
    }
}

/// A timed dialogue turn formatted in natural request-reply or fact-reaction format.
public struct ReelDialogue: Codable, Sendable, Equatable, JSONSchemaConvertible {
    public var speaker: String
    public var text: String
    public var deliveryEmotion: String
    public var spokenDurationSeconds: Double
    public var pauseAfterSeconds: Double

    public init(speaker: String, text: String, deliveryEmotion: String, spokenDurationSeconds: Double, pauseAfterSeconds: Double) {
        self.speaker = speaker
        self.text = text
        self.deliveryEmotion = deliveryEmotion
        self.spokenDurationSeconds = spokenDurationSeconds
        self.pauseAfterSeconds = pauseAfterSeconds
    }

    enum CodingKeys: String, CodingKey {
        case speaker
        case text
        case deliveryEmotion = "delivery_emotion"
        case spokenDurationSeconds = "spoken_duration_seconds"
        case pauseAfterSeconds = "pause_after_seconds"
    }

    public static func schema() -> SchemaDefinition {
        SchemaDefinition(
            title: "dialogue",
            properties: [
                SchemaProperty(name: "speaker", type: "string", description: "Name of the speaking character.", required: true),
                SchemaProperty(name: "text", type: "string", description: "Spoken dialogue line in conversational Hindi/Hinglish.", required: true),
                SchemaProperty(name: "delivery_emotion", type: "string", description: "Facial expression and delivery emotion.", required: true),
                SchemaProperty(name: "spoken_duration_seconds", type: "number", description: "Duration of spoken dialogue based on word count and WPS.", required: true, minimum: 0),
                SchemaProperty(name: "pause_after_seconds", type: "number", description: "Comedic pause or beat after the line.", required: true, minimum: 0)
            ],
            additionalProperties: false
        )
    }
}

/// A scene breakdown with mobile 9:16 location, character blocking, and on-screen text popover.
public struct ReelScene: Codable, Sendable, Equatable, JSONSchemaConvertible {
    public var sceneNumber: Int
    public var location: String
    public var characterActions: String
    public var popoverText: String
    public var durationSeconds: Double

    public init(sceneNumber: Int, location: String, characterActions: String, popoverText: String, durationSeconds: Double) {
        self.sceneNumber = sceneNumber
        self.location = location
        self.characterActions = characterActions
        self.popoverText = popoverText
        self.durationSeconds = durationSeconds
    }

    enum CodingKeys: String, CodingKey {
        case sceneNumber = "scene_number"
        case location
        case characterActions = "character_actions"
        case popoverText = "popover_text"
        case durationSeconds = "duration_seconds"
    }

    public static func schema() -> SchemaDefinition {
        SchemaDefinition(
            title: "scene",
            properties: [
                SchemaProperty(name: "scene_number", type: "integer", required: true, minimum: 1),
                SchemaProperty(name: "location", type: "string", description: "Visual scene backdrop suitable for 9:16 mobile frame.", required: true),
                SchemaProperty(name: "character_actions", type: "string", description: "Character blocking, physical actions, and phone interactions.", required: true),
                SchemaProperty(name: "popover_text", type: "string", description: "On-screen text popover, meme caption, or sticker overlay.", required: true),
                SchemaProperty(name: "duration_seconds", type: "number", description: "Total scene duration.", required: true, minimum: 0)
            ],
            additionalProperties: false
        )
    }
}

/// A complete 10-second comedic reel script variation.
public struct ReelJokeVariation: Codable, Sendable, Equatable, JSONSchemaConvertible {
    public var variationIndex: Int
    public var hook: String
    public var dialogues: [ReelDialogue]
    public var scenes: [ReelScene]
    public var humorNotes: String
    public var totalDurationSeconds: Double

    public init(
        variationIndex: Int,
        hook: String,
        dialogues: [ReelDialogue],
        scenes: [ReelScene],
        humorNotes: String,
        totalDurationSeconds: Double
    ) {
        self.variationIndex = variationIndex
        self.hook = hook
        self.dialogues = dialogues
        self.scenes = scenes
        self.humorNotes = humorNotes
        self.totalDurationSeconds = totalDurationSeconds
    }

    enum CodingKeys: String, CodingKey {
        case variationIndex = "variation_index"
        case hook
        case dialogues
        case scenes
        case humorNotes = "humor_notes"
        case totalDurationSeconds = "total_duration_seconds"
    }

    public static func schema() -> SchemaDefinition {
        SchemaDefinition(
            title: "variation",
            properties: [
                SchemaProperty(name: "variation_index", type: "integer", required: true, minimum: 1),
                SchemaProperty(name: "hook", type: "string", description: "Opening punchy text popover / hook appearing in the first 2 seconds.", required: true),
                SchemaProperty(name: "dialogues", type: "array", description: "Sequential dialogue turns in request-reply or fact-reaction pairs.", required: true, itemsSchema: ReelDialogue.schema()),
                SchemaProperty(name: "scenes", type: "array", description: "Scene breakdown with mobile staging and on-screen text overlays.", required: true, itemsSchema: ReelScene.schema()),
                SchemaProperty(name: "humor_notes", type: "string", description: "Explanation of the comedic angle, satirical premise, and punchline.", required: true),
                SchemaProperty(name: "total_duration_seconds", type: "number", description: "Total duration including speech and pauses, fitting within the duration limit.", required: true, minimum: 0, maximum: 30.0)
            ],
            additionalProperties: false
        )
    }
}

/// Typed input payload for ReelJokeMaker.
public struct ReelJokeMakerInput: Codable, Sendable, Equatable, JSONSchemaConvertible {
    /// News article, headline, or factual summary to create a comedic reel about.
    public var news: String
    /// Spoken dialogue language. Defaults to Hindi ("hi-IN").
    public var language: String
    /// Target total reel duration in seconds. Defaults to 10.0.
    public var durationSeconds: Double
    /// Target words-per-second pacing.
    public var wpsRange: ReelWpsRange
    /// Number of comedy script variations to generate (1 to 5). Defaults to 3.
    public var outputCount: Int
    /// Video format. Defaults to mobile vertical reel (9:16).
    public var format: String

    public init(
        news: String,
        language: String = "hi-IN",
        durationSeconds: Double = 10.0,
        wpsRange: ReelWpsRange = ReelWpsRange(min: 2.5, max: 3.5),
        outputCount: Int = 3,
        format: String = "mobile_vertical_9_16"
    ) {
        self.news = news
        self.language = language
        self.durationSeconds = durationSeconds
        self.wpsRange = wpsRange
        self.outputCount = outputCount
        self.format = format
    }

    enum CodingKeys: String, CodingKey {
        case news
        case language
        case durationSeconds = "duration_seconds"
        case wpsRange = "wps_range"
        case outputCount = "output_count"
        case format
    }

    public static func schema() -> SchemaDefinition {
        SchemaDefinition(
            title: "ReelJokeMakerInput",
            properties: [
                SchemaProperty(name: "news", type: "string", description: "News article headline or story summary to convert into a satirical 10-second reel script.", required: true),
                SchemaProperty(name: "language", type: "string", description: "Spoken dialogue language code. Defaults to Hindi as spoken in India (hi-IN).", defaultValue: .string("hi-IN")),
                SchemaProperty(name: "duration_seconds", type: "number", description: "Target total reel duration in seconds. Defaults to 10.0.", defaultValue: .number(10.0), minimum: 5.0, maximum: 30.0),
                SchemaProperty(name: "wps_range", type: "object", description: "Target words-per-second (WPS) pacing range governing dialogue timing.", defaultValue: .object(["min": .number(2.5), "max": .number(3.5)]), nestedSchema: ReelWpsRange.schema()),
                SchemaProperty(name: "output_count", type: "integer", description: "Number of comedic reel variations to generate. Defaults to 3.", defaultValue: .number(3), minimum: 1, maximum: 5),
                SchemaProperty(name: "format", type: "string", description: "Target video presentation format. Defaults to mobile vertical reel (9:16).", defaultValue: .string("mobile_vertical_9_16"))
            ],
            additionalProperties: false,
            examples: [
                .object([
                    "news": .string("City municipal corporation announces free high-speed Wi-Fi in public parks, but routers are installed on top of 50-foot coconut trees."),
                    "language": .string("hi-IN"),
                    "duration_seconds": .number(10.0),
                    "output_count": .number(3)
                ])
            ]
        )
    }
}

/// Typed output payload for ReelJokeMaker.
public struct ReelJokeMakerOutput: Codable, Sendable, Equatable, JSONSchemaConvertible {
    public var keyFacts: [String]
    public var characters: [ReelCharacter]
    public var variations: [ReelJokeVariation]

    public init(keyFacts: [String], characters: [ReelCharacter], variations: [ReelJokeVariation]) {
        self.keyFacts = keyFacts
        self.characters = characters
        self.variations = variations
    }

    enum CodingKeys: String, CodingKey {
        case keyFacts = "key_facts"
        case characters
        case variations
    }

    public static func schema() -> SchemaDefinition {
        SchemaDefinition(
            title: "ReelJokeMakerOutput",
            properties: [
                SchemaProperty(name: "key_facts", type: "array", description: "Core factual news takeaways extracted from the source story.", required: true, itemsSchema: SchemaDefinition(properties: [SchemaProperty(name: "fact", type: "string")])),
                SchemaProperty(name: "characters", type: "array", description: "Cast of comedic characters appearing in the reel.", required: true, itemsSchema: ReelCharacter.schema()),
                SchemaProperty(name: "variations", type: "array", description: "Array of 10-second comedic reel script variations.", required: true, itemsSchema: ReelJokeVariation.schema(), minItems: 1, maxItems: 5)
            ],
            additionalProperties: false
        )
    }
}

/// Provider-independent, versioned ReelJokeMaker agent definition conforming to AgentProtocol.
public enum ReelJokeMakerDefinition: AgentProtocol, FailureRecoverableAgent {
    public typealias Input = ReelJokeMakerInput
    public typealias Output = ReelJokeMakerOutput

    public static let id = "ReelJokeMaker"
    public static let name = "Reel Joke Maker"
    public static let versions: [String] = ["1.0.0"]
    public static var bundle: Bundle { Bundle.module }

    public static func verifyFeasibility(input: ReelJokeMakerInput) -> FeasibilityResult {
        let trimmed = input.news.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.count < 10 {
            return .unfeasible(reason: "News input is too short or empty to extract key facts and comedic angles.")
        }
        return .feasible
    }

    public static func formatFailure(reason: String) -> String {
        "{\"error\":{\"reason\":\"\(reason)\"}}"
    }

    public enum ReelJokeError: Error, Sendable, Equatable {
        case unknownVersion
    }
}
