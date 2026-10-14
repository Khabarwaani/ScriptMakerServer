import Foundation
internal import TypeDecoder

struct SchemaDerivation {
    /// A model with `name: String` becomes an object requiring a string `name`.
    func derive<T: Decodable>(_ type: T.Type) throws -> String {
        let schema = try definition(from: TypeDecoder.decode(type))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(schema), as: UTF8.self)
    }

    private func definition(from info: TypeInfo, depth: Int = 0) throws -> DerivedSchema {
        guard depth < 64 else { throw DerivationFailure.depthLimit }

        switch info {
        case .single(let original, _):
            guard let schema = primitive(original) else {
                throw DerivationFailure.unsupportedType
            }
            return schema

        case .keyed(let type, let fields):
            if let schema = primitive(type) { return schema }
            var properties: [String: DerivedSchema] = [:]
            var required: [String] = []
            for (name, field) in fields {
                properties[name] = try definition(from: field, depth: depth + 1)
                if case .optional = field {} else { required.append(name) }
            }
            return .object(properties, required: required)

        case .dynamicKeyed(_, let key, let value):
            guard case .single(_, let representation) = key,
                  representation == String.self else {
                throw DerivationFailure.unsupportedType
            }
            return .dictionary(try definition(from: value, depth: depth + 1))

        case .unkeyed(let type, let element):
            if let schema = primitive(type) { return schema }
            return .array(try definition(from: element, depth: depth + 1))

        case .optional(let wrapped):
            return .nullable(try definition(from: wrapped, depth: depth + 1))

        case .cyclic, .opaque:
            throw DerivationFailure.unsupportedType
        }
    }

    private func primitive(_ type: Any.Type) -> DerivedSchema? {
        if type == String.self { return .scalar("string") }
        if type == Bool.self { return .scalar("boolean") }
        if type is any BinaryInteger.Type { return .scalar("integer") }
        if type == Float.self || type == Double.self || type == Decimal.self {
            return .scalar("number")
        }
        if type == Date.self { return .scalar("number") }
        if type == Data.self { return .scalar("string", contentEncoding: "base64") }
        if type == UUID.self { return .scalar("string", format: "uuid") }
        if type == URL.self { return .scalar("string", format: "uri-reference") }
        return nil
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
