import Foundation

/// Typed input payload for ShekharJokeGenerator.
public struct ShekharJokeGeneratorInput: Codable, Sendable, Equatable {
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
}
