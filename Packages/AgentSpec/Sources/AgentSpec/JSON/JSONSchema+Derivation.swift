import Foundation
internal import TypeDecoder

extension JSONSchema {
    /// Input: `struct Person: Decodable { let name: String }`.
    /// Output: `{"properties":{"name":{"type":"string"}},"required":["name"],"type":"object"}`.
    public init?<T: Decodable>(_ type: T.Type) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let schema = try? DerivedSchema(type),
              let data = try? encoder.encode(schema),
              let text = String(data: data, encoding: .utf8) else { return nil }
        self.init(rawValue: text)
        guard isValid else { return nil }
    }
}

private enum DerivationFailure: Error {
    case unsupportedType
    case depthLimit
}

private indirect enum DerivedSchema: Encodable {
    case scalar(String, format: String? = nil, contentEncoding: String? = nil)
    case object([String: DerivedSchema], required: [String])
    case dictionary(DerivedSchema)
    case array(DerivedSchema)
    case nullable(DerivedSchema)

    init<T: Decodable>(_ type: T.Type) throws {
        try self.init(TypeDecoder.decode(type))
    }

    private init(_ info: TypeInfo, depth: Int = 0) throws {
        guard depth < 64 else { throw DerivationFailure.depthLimit }

        switch info {
        case .single(let original, _):
            guard let schema = Self(primitive: original) else {
                throw DerivationFailure.unsupportedType
            }
            self = schema

        case .keyed(let type, let fields):
            if let schema = Self(primitive: type) { self = schema; return }
            var properties: [String: DerivedSchema] = [:]
            var required: [String] = []
            for (name, field) in fields {
                properties[name] = try Self(field, depth: depth + 1)
                if case .optional = field {} else { required.append(name) }
            }
            self = .object(properties, required: required)

        case .dynamicKeyed(_, let key, let value):
            guard case .single(_, let representation) = key,
                  representation == String.self else {
                throw DerivationFailure.unsupportedType
            }
            self = .dictionary(try Self(value, depth: depth + 1))

        case .unkeyed(let type, let element):
            if let schema = Self(primitive: type) { self = schema; return }
            self = .array(try Self(element, depth: depth + 1))

        case .optional(let wrapped):
            self = .nullable(try Self(wrapped, depth: depth + 1))

        case .cyclic, .opaque:
            throw DerivationFailure.unsupportedType
        }
    }

    private init?(primitive type: Any.Type) {
        if type == String.self { self = .scalar("string"); return }
        if type == Bool.self { self = .scalar("boolean"); return }
        if type is any BinaryInteger.Type { self = .scalar("integer"); return }
        if type == Float.self || type == Double.self || type == Decimal.self {
            self = .scalar("number"); return
        }
        if type == Date.self { self = .scalar("number"); return }
        if type == Data.self { self = .scalar("string", contentEncoding: "base64"); return }
        if type == UUID.self { self = .scalar("string", format: "uuid"); return }
        if type == URL.self { self = .scalar("string", format: "uri-reference"); return }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case type, format, contentEncoding, properties, required, additionalProperties, items, anyOf
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .scalar(let type, let format, let contentEncoding):
            try container.encode(type, forKey: .type)
            try container.encodeIfPresent(format, forKey: .format)
            try container.encodeIfPresent(contentEncoding, forKey: .contentEncoding)
        case .object(let properties, let required):
            try container.encode("object", forKey: .type)
            try container.encode(properties, forKey: .properties)
            if !required.isEmpty { try container.encode(required, forKey: .required) }
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
