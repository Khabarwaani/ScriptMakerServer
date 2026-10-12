import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public subscript(_ key: String) -> JSONValue? {
        if case .object(let value) = self { return value[key] }
        return nil
    }
    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }
    public var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
    public var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
    public var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
    public var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
    public func data() throws -> Data { try JSONEncoder().encode(self) }
    public func text() throws -> String { String(decoding: try data(), as: UTF8.self) }
    public static func parse(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(Self.self, from: Data(text.utf8))
    }
}

public struct AgentError: Error, Codable, Sendable, Equatable {
    public let code: String
    public let message: String
    public var execution_id: String?
    public init(_ code: String, _ message: String, executionID: String? = nil) {
        self.code = code
        self.message = message
        self.execution_id = executionID
    }
    public var httpStatus: Int {
        switch code {
        case "unknown_agent", "unknown_version", "unknown_execution": 404
        case "invalid_request", "invalid_json", "input_schema_validation_failed", "invalid_agent_definition": 400
        case "provider_unavailable", "provider_initialization_failed", "server_shutting_down",
            "resource_pressure":
            503
        case "unsupported_provider": 400
        default: 500
        }
    }
}
