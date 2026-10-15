import Foundation

/// Typed output payload for ShekharJokeGenerator.
public struct ShekharJokeGeneratorOutput: Codable, Sendable, Equatable {
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
}
