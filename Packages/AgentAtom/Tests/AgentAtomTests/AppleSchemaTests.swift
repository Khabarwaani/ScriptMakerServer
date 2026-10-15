#if canImport(FoundationModels) && (os(macOS) || os(iOS) || os(visionOS))
@testable import AgentAtom
import Foundation
import FoundationModels
import Testing

struct AppleSchemaTests {
    @Test
    func nativeSchemaPreservesRequiredFieldsWithoutChangingSpec() throws {
        if #available(macOS 26, iOS 26, visionOS 26, *) {
            let original = KeyPointsSpec.outputSchema.rawValue
            let schema = try #require(JSONString(original))
            let native = try AppleIntelligenceSession.generationSchema(from: schema)
            let object = try json(native)
            #expect(Set(object["required"] as? [String] ?? []) == ["points", "person"])
            #expect(object["x-order"] as? [String] == ["person", "points"])
            #expect(object["additionalProperties"] as? Bool == false)
            #expect(KeyPointsSpec.outputSchema.rawValue == original)
            #expect(!original.contains("x-order"))
        }
    }

    @Test
    func failureAlternativeKeepsDiscriminators() throws {
        if #available(macOS 26, iOS 26, visionOS 26, *) {
            let schema = try FailableOperationStrategy().schema(for: KeyPointsSpec.outputSchema)
            let native = try AppleIntelligenceSession.generationSchema(from: schema)
            let object = try json(native)
            #expect((object["anyOf"] as? [Any])?.count == 2)
            let definitions = try #require(object["$defs"] as? [String: [String: Any]])
            let failure = try #require(definitions.values.first { value in
                (value["properties"] as? [String: Any])?["domain"] != nil
            })
            let properties = try #require(failure["properties"] as? [String: [String: Any]])
            #expect(properties["domain"]?["enum"] as? [String] == ["AgentAtom.Operation"])
            #expect(properties["code"]?["minimum"] as? Int == 422)
            #expect(properties["code"]?["maximum"] as? Int == 422)
        }
    }

    @Test
    func nestedCollectionsAndNullableProperties() throws {
        if #available(macOS 26, iOS 26, visionOS 26, *) {
            let derived = try #require(JSONSchema(Nested.self))
            let schema = try #require(JSONString(derived.rawValue))
            let object = try json(AppleIntelligenceSession.generationSchema(from: schema))
            #expect(object["required"] as? [String] == ["people"])
            #expect((object["properties"] as? [String: Any])?.count == 2)
            let encoded = String(decoding: try JSONEncoder().encode(AppleIntelligenceSession.generationSchema(from: schema)), as: UTF8.self)
            #expect(encoded.contains("null"))
        }
    }

    @Test
    func emptyObjectAndDictionarySchemas() throws {
        if #available(macOS 26, iOS 26, visionOS 26, *) {
            for schema in [JSONSchema(Empty.self), JSONSchema([String: String].self)] {
                let derived = try #require(schema)
                let value = try #require(JSONString(derived.rawValue))
                _ = try AppleIntelligenceSession.generationSchema(from: value)
            }
        }
    }

    @Test(arguments: ["format", "contentEncoding"])
    func unsupportedConstraintsFailInsteadOfDisappearing(key: String) throws {
        if #available(macOS 26, iOS 26, visionOS 26, *) {
            let data = try JSONSerialization.data(withJSONObject: ["type": "string", key: "unsupported"])
            let schema = try #require(JSONString(String(decoding: data, as: UTF8.self)))
            #expect(throws: AgenticError.operationFailed(reason: "Apple guided generation does not support schema constraint: \(key).")) {
                try AppleIntelligenceSession.generationSchema(from: schema)
            }
        }
    }

    @Test
    func numericEnumsCannotSilentlyLoseTheirConstraint() throws {
        if #available(macOS 26, iOS 26, visionOS 26, *) {
            let schema: JSONString = #"{"type":"integer","enum":[422]}"#
            #expect(throws: AgenticError.operationFailed(reason: "Apple guided generation supports enum constraints only for strings.")) {
                try AppleIntelligenceSession.generationSchema(from: schema)
            }
        }
    }

    @available(macOS 26, iOS 26, visionOS 26, *)
    private func json(_ schema: GenerationSchema) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(schema)) as? [String: Any])
    }
}

private struct Nested: Decodable {
    let people: [Person]
    let note: String?
    struct Person: Decodable { let name: String }
}
private struct Empty: Decodable {}
#endif
