public struct JSONSchema: Sendable, Equatable {
    public let rawValue: String

    public init?(_ value: String) {
        do {
            try Self.validate(value)
        } catch {
            return nil
        }
        rawValue = value
    }

    public init?<T: Decodable>(_ type: T.Type) {
        guard let value = try? Self.derive(type) else { return nil }
        self.init(value)
    }
}
