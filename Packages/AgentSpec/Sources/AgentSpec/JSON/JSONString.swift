import Foundation

public struct JSONString: Sendable, Equatable {
    public let rawValue: String

    public init?(_ value: String) {
        let data = Data(value.utf8)
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            rawValue = value
        } catch {
            return nil
        }
    }
}

extension JSONString: ExpressibleByStringLiteral {
    /// Invalid literals terminate execution.
    public init(stringLiteral value: String) {
        guard let json = Self(value) else {
            preconditionFailure("Invalid JSON string literal")
        }
        self = json
    }
}

extension JSONString: CustomStringConvertible {
    public var description: String {
        do {
            let object = try JSONSerialization.jsonObject(
                with: Data(rawValue.utf8),
                options: [.fragmentsAllowed]
            )
            let data = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
            )
            return String(data: data, encoding: .utf8) ?? rawValue
        } catch {
            return rawValue
        }
    }
}

extension JSONString: CustomDebugStringConvertible {
    public var debugDescription: String { description }
}
