import Foundation

public struct AgenticFailure: Codable, Sendable, Equatable {
    public let reason: String
    public init(reason: String) { self.reason = reason }
}

public enum AgenticResult<Success: Sendable>: Sendable {
    case success(Success)
    case failure(AgenticFailure)
}

extension AgenticResult: Equatable where Success: Equatable {}

/// Decodes the envelope independently of caller-supplied domain key strategies.
enum AgenticEnvelope: Decodable {
    case success(JSONValue)
    case failure(AgenticFailure)

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let status = try container.decode(String.self, forKey: Key("status"))
        let keys = Set(container.allKeys.map(\.stringValue))
        switch status {
        case "success" where keys == ["status", "output"]:
            self = .success(try container.decode(JSONValue.self, forKey: Key("output")))
        case "failure" where keys == ["status", "failure"]:
            let failure = try container.nestedContainer(keyedBy: Key.self, forKey: Key("failure"))
            guard Set(failure.allKeys.map(\.stringValue)) == ["reason"] else {
                throw Self.invalid(decoder)
            }
            self = .failure(AgenticFailure(reason: try failure.decode(String.self, forKey: Key("reason"))))
        default:
            throw Self.invalid(decoder)
        }
    }

    private static func invalid(_ decoder: any Decoder) -> DecodingError {
        .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid agentic outcome envelope."))
    }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { return nil }
    }
}

/// Preserves JSON number precision while separating domain decoding from envelope decoding.
indirect enum JSONValue: Codable {
    case null
    case bool(Bool)
    case string(String)
    case integer(Int64)
    case unsigned(UInt64)
    case number(Decimal)
    case floating(Double)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let result = try? value.decode(Bool.self) {
            self = .bool(result)
        } else if let result = try? value.decode(String.self) {
            self = .string(result)
        } else if let result = try? value.decode(Int64.self) {
            self = .integer(result)
        } else if let result = try? value.decode(UInt64.self) {
            self = .unsigned(result)
        } else if let result = try? value.decode(Decimal.self) {
            self = .number(result)
        } else if let result = try? value.decode(Double.self) {
            self = .floating(result)
        } else if let result = try? value.decode([JSONValue].self) {
            self = .array(result)
        } else {
            self = .object(try value.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let result): try value.encode(result)
        case .string(let result): try value.encode(result)
        case .integer(let result): try value.encode(result)
        case .unsigned(let result): try value.encode(result)
        case .number(let result): try value.encode(result)
        case .floating(let result): try value.encode(result)
        case .array(let result): try value.encode(result)
        case .object(let result): try value.encode(result)
        }
    }
}
