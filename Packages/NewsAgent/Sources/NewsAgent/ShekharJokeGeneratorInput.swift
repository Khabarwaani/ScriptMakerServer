import Foundation

/// Typed input payload for ShekharJokeGenerator.
public struct ShekharJokeGeneratorInput: Codable, Sendable, Equatable {
    /// Number of winning news joke packages to return in the items output array. Defaults to 1.
    public var outputCount: Int
    /// Number of news stories to research and evaluate. Defaults to 3.
    public var newsCount: Int
    /// Number of jokes per category to evaluate. Defaults to 2.
    public var jokesPerCategory: Int

    public init(
        outputCount: Int = 1,
        newsCount: Int = 3,
        jokesPerCategory: Int = 2
    ) {
        self.outputCount = outputCount
        self.newsCount = newsCount
        self.jokesPerCategory = jokesPerCategory
    }

    enum CodingKeys: String, CodingKey {
        case outputCount = "output_count"
        case newsCount = "news_count"
        case jokesPerCategory = "jokes_per_category"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.outputCount = try container.decodeIfPresent(Int.self, forKey: .outputCount) ?? 1
        self.newsCount = try container.decodeIfPresent(Int.self, forKey: .newsCount) ?? 3
        self.jokesPerCategory = try container.decodeIfPresent(Int.self, forKey: .jokesPerCategory) ?? 2
    }
}
