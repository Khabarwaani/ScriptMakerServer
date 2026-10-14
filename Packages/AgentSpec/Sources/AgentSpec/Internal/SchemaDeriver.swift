import Foundation

/// Observes ordinary synthesized decoding. It does not inspect Swift ABI layouts.
extension JSONSchema {
    static func derive<T: Decodable>(_ type: T.Type) throws -> String {
        let session = DerivationSession()
        let node = SchemaNode()
        _ = try session.decode(type, into: node, path: [])
        if let failure = session.failure { throw failure }
        let data = try JSONSerialization.data(
            withJSONObject: node.definition,
            options: [.sortedKeys, .fragmentsAllowed]
        )
        return String(decoding: data, as: UTF8.self)
    }
}

private final class SchemaNode {
    var definition: [String: Any] = [:]
    var properties: [String: Any] = [:]
    var required: [String] = []
}

private final class DerivationSession {
    var activeTypes: Set<ObjectIdentifier> = []
    var failure: SchemaDerivationError?
    private var visits = 0

    func unsupported(_ type: Any.Type, _ reason: String) -> SchemaDerivationError {
        let error = SchemaDerivationError(typeName: String(reflecting: type), reason: reason)
        if failure == nil { failure = error }
        return error
    }

    func decode<T: Decodable>(
        _ type: T.Type,
        into node: SchemaNode,
        path: [any CodingKey]
    ) throws -> T {
        visits += 1
        guard visits <= 1024, path.count < 64 else {
            throw unsupported(type, "Model exceeds derivation depth or size limits")
        }

        if type == Bool.self {
            node.definition = ["type": "boolean"]
            return Bool(true) as! T
        }
        if type == String.self {
            node.definition = ["type": "string"]
            return String("schema") as! T
        }
        if type == Double.self {
            node.definition = ["type": "number"]
            return Double(1) as! T
        }
        if type == Float.self {
            node.definition = ["type": "number"]
            return Float(1) as! T
        }
        if type == Int.self {
            node.definition = ["type": "integer"]
            return Int(1) as! T
        }
        if type == Int8.self {
            node.definition = ["type": "integer"]
            return Int8(1) as! T
        }
        if type == Int16.self {
            node.definition = ["type": "integer"]
            return Int16(1) as! T
        }
        if type == Int32.self {
            node.definition = ["type": "integer"]
            return Int32(1) as! T
        }
        if type == Int64.self {
            node.definition = ["type": "integer"]
            return Int64(1) as! T
        }
        if type == UInt.self {
            node.definition = ["type": "integer"]
            return UInt(1) as! T
        }
        if type == UInt8.self {
            node.definition = ["type": "integer"]
            return UInt8(1) as! T
        }
        if type == UInt16.self {
            node.definition = ["type": "integer"]
            return UInt16(1) as! T
        }
        if type == UInt32.self {
            node.definition = ["type": "integer"]
            return UInt32(1) as! T
        }
        if type == UInt64.self {
            node.definition = ["type": "integer"]
            return UInt64(1) as! T
        }

        // Match JSONDecoder's default Foundation representations.
        if type == Date.self {
            node.definition = ["type": "number"]
            return Date(timeIntervalSinceReferenceDate: 0) as! T
        }
        if type == Data.self {
            node.definition = ["type": "string", "contentEncoding": "base64"]
            return Data() as! T
        }
        if type == UUID.self {
            node.definition = ["type": "string", "format": "uuid"]
            return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) as! T
        }
        if type == URL.self {
            node.definition = ["type": "string", "format": "uri"]
            return URL(string: "https://example.invalid")! as! T
        }
        if type == Decimal.self {
            node.definition = ["type": "number"]
            return Decimal(1) as! T
        }

        let identifier = ObjectIdentifier(type)
        guard activeTypes.insert(identifier).inserted else {
            throw unsupported(type, "Recursive models require an explicit output schema")
        }
        defer { activeTypes.remove(identifier) }

        do {
            if let collection = type as? any SchemaCollection.Type {
                return try collection.derive(session: self, node: node, path: path) as! T
            }
            let value = try T(from: ModelDecoder(node: node, session: self, codingPath: path))
            if let failure { throw failure }
            guard !node.definition.isEmpty else {
                throw unsupported(type, "Decoding did not reveal a model structure")
            }
            return value
        } catch let error as SchemaDerivationError {
            throw error
        } catch {
            throw unsupported(type, "Custom decoding could not be derived; provide an explicit output schema")
        }
    }
}

private protocol SchemaCollection {
    static func derive(
        session: DerivationSession,
        node: SchemaNode,
        path: [any CodingKey]
    ) throws -> Any
}

extension Array: SchemaCollection where Element: Decodable {
    fileprivate static func derive(
        session: DerivationSession, node: SchemaNode, path: [any CodingKey]
    ) throws -> Any {
        let child = SchemaNode()
        let value = try session.decode(Element.self, into: child, path: path + [SchemaKey(index: 0)])
        node.definition = ["type": "array", "items": child.definition]
        return [value]
    }
}

extension Optional: SchemaCollection where Wrapped: Decodable {
    fileprivate static func derive(
        session: DerivationSession, node: SchemaNode, path: [any CodingKey]
    ) throws -> Any {
        let child = SchemaNode()
        let value = try session.decode(Wrapped.self, into: child, path: path)
        node.definition = ["anyOf": [child.definition, ["type": "null"]]]
        return Optional.some(value) as Any
    }
}

extension Dictionary: SchemaCollection where Key: Decodable, Value: Decodable {
    fileprivate static func derive(
        session: DerivationSession, node: SchemaNode, path: [any CodingKey]
    ) throws -> Any {
        guard Key.self == String.self else {
            throw session.unsupported(Self.self, "Only string-keyed dictionaries are supported")
        }
        let child = SchemaNode()
        _ = try session.decode(Value.self, into: child, path: path + [SchemaKey(stringValue: "value")])
        node.definition = ["type": "object", "additionalProperties": child.definition]
        return Self()
    }
}

private struct SchemaKey: CodingKey {
    let stringValue: String
    let intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    init(index: Int) { self.init(intValue: index) }
}

private struct ModelDecoder: Decoder {
    let node: SchemaNode
    let session: DerivationSession
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any] = [:]

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard node.definition.isEmpty else {
            throw session.unsupported(Key.self, "Multiple decoding containers require an explicit schema")
        }
        // Unknown response fields are permitted, matching JSONDecoder behavior.
        node.definition = ["type": "object", "properties": [String: Any]()]
        return KeyedDecodingContainer(ModelContainer<Key>(decoder: self))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw session.unsupported(Self.self, "Custom unkeyed decoding requires an explicit schema")
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        throw session.unsupported(Self.self, "Custom single-value decoding requires an explicit schema")
    }
}

private struct ModelContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let decoder: ModelDecoder
    var codingPath: [any CodingKey] { decoder.codingPath }
    var allKeys: [Key] {
        _ = decoder.session.unsupported(Key.self, "Dynamic keys and synthesized enums require an explicit schema")
        return []
    }

    func contains(_ key: Key) -> Bool {
        _ = decoder.session.unsupported(Key.self, "Conditional decoding requires an explicit schema")
        return false
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        throw decoder.session.unsupported(Key.self, "Custom null checks require an explicit schema")
    }

    private func capture<T: Decodable>(
        _ type: T.Type, key: Key, required: Bool
    ) throws -> T {
        guard decoder.node.properties[key.stringValue] == nil else {
            throw decoder.session.unsupported(type, "Repeated decoding of a key requires an explicit schema")
        }
        let child = SchemaNode()
        let value = try decoder.session.decode(
            type, into: child, path: codingPath + [key]
        )
        decoder.node.properties[key.stringValue] = required
            ? child.definition
            : ["anyOf": [child.definition, ["type": "null"]]]
        if required { decoder.node.required.append(key.stringValue) }
        decoder.node.definition["properties"] = decoder.node.properties
        if !decoder.node.required.isEmpty {
            decoder.node.definition["required"] = decoder.node.required
        }
        return value
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        try capture(type, key: key, required: true)
    }

    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        try capture(type, key: key, required: false)
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        try capture(type, key: key, required: true)
    }

    func decodeIfPresent(_ type: Bool.Type, forKey key: Key) throws -> Bool? {
        try capture(type, key: key, required: false)
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        try capture(type, key: key, required: true)
    }

    func decodeIfPresent(_ type: String.Type, forKey key: Key) throws -> String? {
        try capture(type, key: key, required: false)
    }

    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        try capture(type, key: key, required: true)
    }

    func decodeIfPresent(_ type: Double.Type, forKey key: Key) throws -> Double? {
        try capture(type, key: key, required: false)
    }

    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        try capture(type, key: key, required: true)
    }

    func decodeIfPresent(_ type: Float.Type, forKey key: Key) throws -> Float? {
        try capture(type, key: key, required: false)
    }

    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        try capture(type, key: key, required: true)
    }

    func decodeIfPresent(_ type: Int.Type, forKey key: Key) throws -> Int? {
        try capture(type, key: key, required: false)
    }

    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        try capture(type, key: key, required: true)
    }

    func decodeIfPresent(_ type: Int8.Type, forKey key: Key) throws -> Int8? {
        try capture(type, key: key, required: false)
    }

    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        try capture(type, key: key, required: true)
    }

    func decodeIfPresent(_ type: Int16.Type, forKey key: Key) throws -> Int16? {
        try capture(type, key: key, required: false)
    }

    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        try capture(type, key: key, required: true)
    }

    func decodeIfPresent(_ type: Int32.Type, forKey key: Key) throws -> Int32? {
        try capture(type, key: key, required: false)
    }

    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        try capture(type, key: key, required: true)
    }

    func decodeIfPresent(_ type: Int64.Type, forKey key: Key) throws -> Int64? {
        try capture(type, key: key, required: false)
    }

    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        try capture(type, key: key, required: true)
    }

    func decodeIfPresent(_ type: UInt.Type, forKey key: Key) throws -> UInt? {
        try capture(type, key: key, required: false)
    }

    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        try capture(type, key: key, required: true)
    }

    func decodeIfPresent(_ type: UInt8.Type, forKey key: Key) throws -> UInt8? {
        try capture(type, key: key, required: false)
    }

    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        try capture(type, key: key, required: true)
    }

    func decodeIfPresent(_ type: UInt16.Type, forKey key: Key) throws -> UInt16? {
        try capture(type, key: key, required: false)
    }

    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        try capture(type, key: key, required: true)
    }

    func decodeIfPresent(_ type: UInt32.Type, forKey key: Key) throws -> UInt32? {
        try capture(type, key: key, required: false)
    }

    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        try capture(type, key: key, required: true)
    }

    func decodeIfPresent(_ type: UInt64.Type, forKey key: Key) throws -> UInt64? {
        try capture(type, key: key, required: false)
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type, forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        throw decoder.session.unsupported(type, "Custom nested containers require an explicit schema")
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        throw decoder.session.unsupported(Key.self, "Custom nested arrays require an explicit schema")
    }

    func superDecoder() throws -> any Decoder {
        throw decoder.session.unsupported(Key.self, "Inherited decoding requires an explicit schema")
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        throw decoder.session.unsupported(Key.self, "Inherited decoding requires an explicit schema")
    }
}
