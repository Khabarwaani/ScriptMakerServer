import Foundation
import ReelJokeMaker

extension ReelWpsRange: JSONSchemaConvertible {
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

extension ReelCharacter: JSONSchemaConvertible {
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

extension ReelDialogue: JSONSchemaConvertible {
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

extension ReelScene: JSONSchemaConvertible {
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

extension ReelJokeVariation: JSONSchemaConvertible {
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

extension ReelJokeMakerInput: JSONSchemaConvertible {
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
            additionalProperties: false
        )
    }
}

extension ReelJokeMakerOutput: JSONSchemaConvertible {
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
