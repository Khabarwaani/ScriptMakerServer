import Foundation

/// Pacing range governing dialogue speech pacing in words per second.
public struct ReelWpsRange: Codable, Sendable, Equatable {
    public var min: Double
    public var max: Double

    public init(min: Double = 2.5, max: Double = 3.5) {
        self.min = min
        self.max = max
    }
}

/// Typed input payload for ReelJokeMaker.
public struct ReelJokeMakerInput: Codable, Sendable, Equatable {
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
}

/// Character profile with visual details and clothing for vertical mobile framing.
public struct ReelCharacter: Codable, Sendable, Equatable {
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
}

/// A timed dialogue turn formatted in natural request-reply or fact-reaction format.
public struct ReelDialogue: Codable, Sendable, Equatable {
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
}

/// A scene breakdown with mobile 9:16 location, character blocking, and on-screen text popover.
public struct ReelScene: Codable, Sendable, Equatable {
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
}

/// A complete 10-second comedic reel script variation.
public struct ReelJokeVariation: Codable, Sendable, Equatable {
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
}

/// Typed output payload for ReelJokeMaker.
public struct ReelJokeMakerOutput: Codable, Sendable, Equatable {
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
}

/// Provider-independent, versioned ReelJokeMaker agent definition.
public enum ReelJokeMakerDefinition: Sendable {
    public static let id = "ReelJokeMaker"
    public static let versions: [String] = ["1.0.0"]
    public static var bundle: Bundle { Bundle.module }

    public static func directory(version: String) throws -> URL {
        guard versions.contains(version),
              let url = bundle.url(forResource: version, withExtension: nil) else {
            throw ReelJokeError.unknownVersion
        }
        return url
    }

    public static func role(version: String) throws -> String {
        let dir = try directory(version: version)
        return try String(contentsOf: dir.appendingPathComponent("role.md"), encoding: .utf8)
    }

    public static func instructions(version: String) throws -> String {
        let dir = try directory(version: version)
        let file = dir.appendingPathComponent("instructions.md")
        return try String(contentsOf: file, encoding: .utf8)
    }

    public static func outputSchema(version: String) throws -> String {
        let dir = try directory(version: version)
        return try String(contentsOf: dir.appendingPathComponent("output.schema.json"), encoding: .utf8)
    }

    public static func inputSchema(version: String) throws -> String? {
        let dir = try directory(version: version)
        let file = dir.appendingPathComponent("input.schema.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try String(contentsOf: file, encoding: .utf8)
    }

    public enum ReelJokeError: Error, Sendable, Equatable {
        case unknownVersion
    }
}
