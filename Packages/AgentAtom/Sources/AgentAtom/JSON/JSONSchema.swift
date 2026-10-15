import Foundation
// TypeDecoder and TypeInfo inspect Decodable model structure.
internal import TypeDecoder

public struct JSONSchema: Sendable, Equatable {
    public let rawValue: String
    let node: SchemaNode

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.rawValue == rhs.rawValue }

    init(node: SchemaNode) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        rawValue = String(decoding: try encoder.encode(node), as: UTF8.self)
        self.node = node
    }

    /// Derives output structure from a Decodable model, without domain validation.
    public init?<T: Decodable>(_ type: T.Type) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let schema = try? SchemaNode(type),
            let data = try? encoder.encode(schema),
            let text = String(data: data, encoding: .utf8),
            let json = JSONString(text)
        else {
            return nil
        }
        rawValue = json.rawValue
        node = schema
    }
}

extension JSONSchema: CustomStringConvertible {
    public var description: String { JSONString(rawValue)?.description ?? rawValue }
}

extension JSONSchema: CustomDebugStringConvertible {
    public var debugDescription: String { description }
}

// Internal nodes are shared by composition and provider translation.
extension JSONSchema {
    private enum Constants {
        // Bounds recursive schema conversion.
        static let maximumDepth = 64
        static let emptyObject = Data("{}".utf8)
    }

    // Derivation fails for unsupported models or excessive nesting.
    private enum DerivationFailure: Error {
        case unsupportedType
        case depthLimit
    }

    // Schema shapes serialized by Foundation's JSONEncoder.
    indirect enum SchemaNode: Encodable, Sendable, Equatable {
        case scalar(String, format: String? = nil, contentEncoding: String? = nil)
        case object([String: SchemaNode], required: [String], closed: Bool = false)
        case union([SchemaNode])
        case choices([String])
        case dictionary(SchemaNode)
        case array(SchemaNode)
        case nullable(SchemaNode)

        // Called only by the schema initializer in this file.
        init<T: Decodable>(_ type: T.Type) throws {
            try self.init(TypeDecoder.decode(type))
        }

        private init(_ info: TypeInfo, depth: Int = 0) throws {
            guard depth < Constants.maximumDepth else {
                throw DerivationFailure.depthLimit
            }

            switch info {
            case .single(let original, _):
                guard let schema = Self(primitive: original) else {
                    throw DerivationFailure.unsupportedType
                }
                self = schema

            case .keyed(let type, let fields):
                if let schema = Self(primitive: type) {
                    self = schema
                    return
                }
                var properties: [String: SchemaNode] = [:]
                var required: [String] = []
                for (name, field) in fields {
                    properties[name] = try Self(field, depth: depth + 1)
                    if case .optional = field {
                        continue
                    }
                    required.append(name)
                }
                self = .object(properties, required: required)

            case .dynamicKeyed(_, let key, let value):
                guard case .single(let originalKeyType, _) = key,
                    originalKeyType == String.self
                else {
                    throw DerivationFailure.unsupportedType
                }
                self = .dictionary(try Self(value, depth: depth + 1))

            case .unkeyed(let type, let element):
                if let schema = Self(primitive: type) {
                    self = schema
                    return
                }
                self = .array(try Self(element, depth: depth + 1))

            case .optional(let wrapped):
                self = .nullable(try Self(wrapped, depth: depth + 1))

            case .cyclic:
                throw DerivationFailure.unsupportedType

            case .opaque(let type):
                guard let modelType = type as? any Decodable.Type else {
                    throw DerivationFailure.unsupportedType
                }
                self = try Self(emptyModel: modelType)
            }
        }

        private init<T: Decodable>(emptyModel type: T.Type) throws {
            let model = try JSONDecoder().decode(type, from: Constants.emptyObject)
            let fields = Mirror(reflecting: model)
            // Accept empty structs, not arbitrary opaque decoding.
            guard fields.displayStyle == .struct, fields.children.isEmpty else {
                throw DerivationFailure.unsupportedType
            }
            self = .object([:], required: [])
        }

        private enum CodingKeys: String, CodingKey {
            case type, format, contentEncoding
            case properties, required, additionalProperties
            case items, anyOf
            case enumeration = "enum"
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .scalar(let type, let format, let contentEncoding):
                try container.encode(type, forKey: .type)
                try container.encodeIfPresent(format, forKey: .format)
                try container.encodeIfPresent(contentEncoding, forKey: .contentEncoding)
            case .object(let properties, let required, let closed):
                try container.encode("object", forKey: .type)
                try container.encode(properties, forKey: .properties)
                if closed { try container.encode(false, forKey: .additionalProperties) }
                if !required.isEmpty {
                    try container.encode(required, forKey: .required)
                }
            case .union(let alternatives):
                try container.encode(alternatives, forKey: .anyOf)
            case .choices(let values):
                try container.encode("string", forKey: .type)
                try container.encode(values, forKey: .enumeration)
            case .dictionary(let value):
                try container.encode("object", forKey: .type)
                try container.encode(value, forKey: .additionalProperties)
            case .array(let element):
                try container.encode("array", forKey: .type)
                try container.encode(element, forKey: .items)
            case .nullable(let wrapped):
                try container.encode([wrapped, .scalar("null")], forKey: .anyOf)
            }
        }
    }
}

extension JSONSchema.SchemaNode {
    fileprivate init?(primitive type: Any.Type) {
        switch type {
        case is String.Type:
            self = .scalar("string")
        case is Bool.Type:
            self = .scalar("boolean")
        case is any BinaryInteger.Type:
            self = .scalar("integer")
        case is Float.Type, is Double.Type, is Decimal.Type, is Date.Type:
            self = .scalar("number")
        case is Data.Type:
            self = .scalar("string", contentEncoding: "base64")
        case is UUID.Type:
            self = .scalar("string", format: "uuid")
        case is URL.Type:
            self = .scalar("string", format: "uri-reference")
        default:
            return nil
        }
    }
}
