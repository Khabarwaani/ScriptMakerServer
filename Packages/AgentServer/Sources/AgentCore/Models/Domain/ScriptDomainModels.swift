import Foundation

/// Pacing range governing dialogue speech timing in words per second.
public struct WpsRange: Codable, Sendable, Equatable, JSONSchemaConvertible {
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

/// Timing breakdown for a single scene.
public struct SceneTiming: Codable, Sendable, Equatable, JSONSchemaConvertible {
    public var sceneNumber: Int
    public var dialogueDurationSeconds: Double
    public var nonDialogueDurationSeconds: Double
    public var totalDurationSeconds: Double

    public init(
        sceneNumber: Int,
        dialogueDurationSeconds: Double,
        nonDialogueDurationSeconds: Double,
        totalDurationSeconds: Double
    ) {
        self.sceneNumber = sceneNumber
        self.dialogueDurationSeconds = dialogueDurationSeconds
        self.nonDialogueDurationSeconds = nonDialogueDurationSeconds
        self.totalDurationSeconds = totalDurationSeconds
    }

    public static func schema() -> SchemaDefinition {
        SchemaDefinition(
            title: "scene_timing",
            properties: [
                SchemaProperty(name: "scene_number", type: "integer", description: "1-based index of the scene.", required: true, minimum: 1),
                SchemaProperty(name: "dialogue_duration_seconds", type: "number", description: "Spoken dialogue duration calculated from dialogue word count and wps_range.", required: true, minimum: 0),
                SchemaProperty(name: "non_dialogue_duration_seconds", type: "number", description: "Duration allocated to non-dialogue elements (actions, pauses, transitions).", required: true, minimum: 0),
                SchemaProperty(name: "total_duration_seconds", type: "number", description: "Total scene duration (dialogue + non-dialogue).", required: true, minimum: 0)
            ],
            additionalProperties: false
        )
    }
}
