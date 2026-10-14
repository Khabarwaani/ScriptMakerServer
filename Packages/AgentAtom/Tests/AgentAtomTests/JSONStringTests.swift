@testable import AgentAtom
import Foundation
import Testing

struct JSONStringTests {
    @Test
    func testJSONStringAcceptsAllShapesAndPreservesText() {
        let validTexts = [
            " {} \n",
            "[]",
            #""hello""#,
            "42",
            "-1.25e2",
            "true",
            "false",
            "null",
            #"""
            {
                "b": 2,
                "a": 1
            }
            """#
        ]
        for text in validTexts {
            #expect(JSONString(text)?.rawValue == text, "\(text)")
        }

        let invalidTexts = [
            "",
            "invalid",
            "{",
            #"{"a":}"#,
            "NaN",
            "true false"
        ]
        for text in invalidTexts {
            #expect(JSONString(text) == nil, "\(text)")
        }

        let compactLiteral: JSONString = #"{"b":2,"a":1}"#
        #expect(compactLiteral == JSONString(compactLiteral.rawValue))
        #expect(compactLiteral.description == compactLiteral.debugDescription)
        #expect(compactLiteral.description.contains("\n"))
        #expect(JSONString(compactLiteral.description)?.description == compactLiteral.description)
    }

    @Test
    func testJSONStringUsesFoundationAcceptanceRules() {
        let foundationDependentTexts = [
            "[1,]",
            #"{"a":1,}"#,
            "01",
            "+1"
        ]
        for text in foundationDependentTexts {
            let accepted = (try? JSONSerialization.jsonObject(
                with: Data(text.utf8), options: [.fragmentsAllowed]
            )) != nil
            #expect((JSONString(text) != nil) == accepted, "\(text)")
        }
    }
}
