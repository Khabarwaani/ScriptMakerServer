import Foundation

public enum ServerEnvironment: String, Sendable, Decodable {
    case production, development, testing
}

/// Shared by the executable and test launchers; selection happens at startup.
public struct TestingPortConfiguration: Sendable, Decodable {
    public let min: Int
    public let max: Int
    public let maxAttempts: Int
    public var range: ClosedRange<Int> { min...max }

    public init(min: Int = 9000, max: Int = 9999, maxAttempts: Int = 30) throws {
        guard (1...65535).contains(min), (min...65535).contains(max), (1...30).contains(maxAttempts) else {
            throw ServerConfiguration.ConfigurationError.invalidPortConfiguration
        }
        self.min = min
        self.max = max
        self.maxAttempts = maxAttempts
    }

    private enum CodingKeys: String, CodingKey { case min, max, maxAttempts = "max_attempts" }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            min: values.decodeIfPresent(Int.self, forKey: .min) ?? 9000,
            max: values.decodeIfPresent(Int.self, forKey: .max) ?? 9999,
            maxAttempts: values.decodeIfPresent(Int.self, forKey: .maxAttempts) ?? 30)
    }
}

struct PortConfiguration: Decodable {
    var production: Int?
    var development: Int?
    var testing: TestingPortConfiguration?
}
