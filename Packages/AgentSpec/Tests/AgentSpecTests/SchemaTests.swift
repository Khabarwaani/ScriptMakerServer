import AgentSpec
import Foundation
import XCTest

final class SchemaTests: XCTestCase {
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

    func testNestedModelsCodingKeysAndOptionalFields() throws {
        let schema = try XCTUnwrap(JSONSchema(Response.self))
        let root = try object(schema.rawValue)
        XCTAssertEqual(root["type"] as? String, "object")
        XCTAssertEqual(Set(root["required"] as? [String] ?? []), ["display_name", "children", "metadata"])
        XCTAssertNil(root["additionalProperties"])
        let properties = try XCTUnwrap(root["properties"] as? [String: Any])
        XCTAssertNil(properties["name"])
        XCTAssertEqual(try objectValue(properties["display_name"])["type"] as? String, "string")
        let children = try objectValue(properties["children"])
        XCTAssertEqual(children["type"] as? String, "array")
        let child = try objectValue(children["items"])
        XCTAssertEqual(child["required"] as? [String], ["value"])
        let metadata = try objectValue(properties["metadata"])
        XCTAssertEqual(metadata["type"] as? String, "object")
        XCTAssertEqual(try objectValue(metadata["additionalProperties"])["type"] as? String, "integer")
        let note = try objectValue(properties["note"])
        let alternatives = try XCTUnwrap(note["anyOf"] as? [[String: Any]])
        XCTAssertEqual(alternatives.compactMap { $0["type"] as? String }, ["string", "null"])
        XCTAssertEqual(schema.description, schema.debugDescription)
        XCTAssertNotNil(JSONString(schema.description))
    }

    func testCollectionsAndEmptyModel() throws {
        try assertSchema([String].self, equals: #"{"type":"array","items":{"type":"string"}}"#)
        try assertSchema([String: Bool].self, equals: #"{"type":"object","additionalProperties":{"type":"boolean"}}"#)
        try assertSchema(String?.self, equals: #"{"anyOf":[{"type":"string"},{"type":"null"}]}"#)
        try assertSchema(Empty.self, equals: #"{"type":"object","properties":{}}"#)
    }

    func testUnsupportedModelsDoNotProducePermissiveSchemas() {
        XCTAssertNil(JSONSchema([Int: String].self))
        XCTAssertNil(JSONSchema([UUID: String].self))
        XCTAssertNil(JSONSchema(Recursive.self))
        XCTAssertNil(JSONSchema(Rejecting.self))
        XCTAssertNil(JSONSchema(Opaque.self))
        XCTAssertNil(JSONSchema(Choice.self))
    }

    func testDepthLimitRejectsExcessiveNesting() {
        var model: any Decodable.Type = String.self
        for _ in 0..<63 {
            model = layer(around: model)
        }
        XCTAssertNotNil(JSONSchema(model))
        model = layer(around: model)
        XCTAssertNil(JSONSchema(model))
    }

    func testDefaultFoundationEncodingMatchesDerivedRepresentations() throws {
        let values = SpecialValues(
            date: Date(timeIntervalSinceReferenceDate: 42),
            data: Data([1, 2]),
            uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            url: URL(string: "https://example.com/path")!,
            decimal: Decimal(string: "12.5")!
        )
        let encoded = try JSONEncoder().encode(values)
        XCTAssertEqual(try JSONDecoder().decode(SpecialValues.self, from: encoded), values)
        let json = try objectValue(JSONSerialization.jsonObject(with: encoded))
        XCTAssertEqual(json["date"] as? Double, 42)
        XCTAssertEqual(json["decimal"] as? Double, 12.5)
        XCTAssertEqual(json["data"] as? String, "AQI=")
        XCTAssertEqual(json["uuid"] as? String, values.uuid.uuidString)
        XCTAssertEqual(json["url"] as? String, values.url.absoluteString)
        XCTAssertNotNil(JSONSchema(SpecialValues.self))
    }

    private func layer<T: Decodable>(around type: T.Type) -> any Decodable.Type {
        Layer<T>.self
    }

    private func assertSchema<T: Decodable>(
        _ type: T.Type,
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let schema = try XCTUnwrap(JSONSchema(type), file: file, line: line)
        XCTAssertEqual(try object(schema.rawValue) as NSDictionary,
                       try object(expected) as NSDictionary, file: file, line: line)
    }

    private func object(_ text: String) throws -> [String: Any] {
        try objectValue(JSONSerialization.jsonObject(with: Data(text.utf8)))
    }

    private func objectValue(_ value: Any?) throws -> [String: Any] {
        try XCTUnwrap(value as? [String: Any])
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
