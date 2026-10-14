@testable import AgentAtom
import Foundation
import Testing

struct SchemaTests {
    @Test
    func testPrimitiveAndFoundationRepresentations() throws {
        try assertSchema(String.self, equals: #"{"type":"string"}"#)
        try assertSchema(Bool.self, equals: #"{"type":"boolean"}"#)
        try assertSchema(Int.self, equals: #"{"type":"integer"}"#)
        try assertSchema(UInt64.self, equals: #"{"type":"integer"}"#)
        try assertSchema(Double.self, equals: #"{"type":"number"}"#)
        try assertSchema(Float.self, equals: #"{"type":"number"}"#)
        try assertSchema(Decimal.self, equals: #"{"type":"number"}"#)
        try assertSchema(Date.self, equals: #"{"type":"number"}"#)
        try assertSchema(Data.self, equals: #"{"type":"string","contentEncoding":"base64"}"#)
        try assertSchema(UUID.self, equals: #"{"type":"string","format":"uuid"}"#)
        try assertSchema(URL.self, equals: #"{"type":"string","format":"uri-reference"}"#)
    }

    @Test
    func testNestedModelsCodingKeysAndOptionalFields() throws {
        let schema = try #require(JSONSchema(Response.self))
        let root = try object(schema.rawValue)
        #expect(root["type"] as? String == "object")
        #expect(Set(root["required"] as? [String] ?? []) == ["display_name", "children", "metadata"])
        #expect(root["additionalProperties"] == nil)
        let properties = try #require(root["properties"] as? [String: Any])
        #expect(properties["name"] == nil)
        #expect(try objectValue(properties["display_name"])["type"] as? String == "string")
        let children = try objectValue(properties["children"])
        #expect(children["type"] as? String == "array")
        let child = try objectValue(children["items"])
        #expect(child["required"] as? [String] == ["value"])
        let metadata = try objectValue(properties["metadata"])
        #expect(metadata["type"] as? String == "object")
        #expect(try objectValue(metadata["additionalProperties"])["type"] as? String == "integer")
        let note = try objectValue(properties["note"])
        let alternatives = try #require(note["anyOf"] as? [[String: Any]])
        #expect(alternatives.compactMap { $0["type"] as? String } == ["string", "null"])
        #expect(schema.description == schema.debugDescription)
        #expect(JSONString(schema.description) != nil)
    }

    @Test
    func testCollectionsAndEmptyModel() throws {
        try assertSchema([String].self, equals: #"{"type":"array","items":{"type":"string"}}"#)
        try assertSchema([String: Bool].self, equals: #"{"type":"object","additionalProperties":{"type":"boolean"}}"#)
        try assertSchema(String?.self, equals: #"{"anyOf":[{"type":"string"},{"type":"null"}]}"#)
        try assertSchema(Empty.self, equals: #"{"type":"object","properties":{}}"#)
    }

    @Test
    func testUnsupportedModelsDoNotProducePermissiveSchemas() {
        #expect(JSONSchema([Int: String].self) == nil)
        #expect(JSONSchema([UUID: String].self) == nil)
        #expect(JSONSchema(Recursive.self) == nil)
        #expect(JSONSchema(Rejecting.self) == nil)
        #expect(JSONSchema(Opaque.self) == nil)
        #expect(JSONSchema(Choice.self) == nil)
    }

    @Test
    func testDepthLimitRejectsExcessiveNesting() {
        var model: any Decodable.Type = String.self
        for _ in 0..<63 {
            model = layer(around: model)
        }
        #expect(JSONSchema(model) != nil)
        model = layer(around: model)
        #expect(JSONSchema(model) == nil)
    }

    @Test
    func testDefaultFoundationEncodingMatchesDerivedRepresentations() throws {
        let values = SpecialValues(
            date: Date(timeIntervalSinceReferenceDate: 42),
            data: Data([1, 2]),
            uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            url: URL(string: "https://example.com/path")!,
            decimal: Decimal(string: "12.5")!
        )
        let encoded = try JSONEncoder().encode(values)
        #expect(try JSONDecoder().decode(SpecialValues.self, from: encoded) == values)
        let json = try objectValue(JSONSerialization.jsonObject(with: encoded))
        #expect(json["date"] as? Double == 42)
        #expect(json["decimal"] as? Double == 12.5)
        #expect(json["data"] as? String == "AQI=")
        #expect(json["uuid"] as? String == values.uuid.uuidString)
        #expect(json["url"] as? String == values.url.absoluteString)
        #expect(JSONSchema(SpecialValues.self) != nil)
    }

    private func layer<T: Decodable>(around type: T.Type) -> any Decodable.Type {
        Layer<T>.self
    }

    private func assertSchema<T: Decodable>(
        _ type: T.Type,
        equals expected: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let schema = try #require(JSONSchema(type), sourceLocation: sourceLocation)
        let actualObject = try object(schema.rawValue) as NSDictionary
        let expectedObject = try object(expected) as NSDictionary
        #expect(actualObject == expectedObject, sourceLocation: sourceLocation)
    }

    private func object(_ text: String) throws -> [String: Any] {
        try objectValue(JSONSerialization.jsonObject(with: Data(text.utf8)))
    }

    private func objectValue(_ value: Any?) throws -> [String: Any] {
        try #require(value as? [String: Any])
    }
}

private struct Response: Decodable {
    let name: String
    let children: [Child]
    let metadata: [String: Int]
    let note: String?

    enum CodingKeys: String, CodingKey {
        case name = "display_name"
        case children, metadata, note
    }
}

private struct Child: Decodable { let value: Bool }
private struct Empty: Decodable {}
private struct Layer<T: Decodable>: Decodable { let value: T }
private struct SpecialValues: Codable, Equatable {
    let date: Date
    let data: Data
    let uuid: UUID
    let url: URL
    let decimal: Decimal
}
private final class Recursive: Decodable { let next: Recursive? }
private enum Choice: String, Decodable { case first, second }

private struct Rejecting: Decodable {
    init(from decoder: any Decoder) throws {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unsupported"))
    }
}

private struct Opaque: Decodable {
    let hidden = 1
    init(from decoder: any Decoder) {}
}
