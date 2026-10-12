import Foundation
import Testing

@testable import AgentCore

@Test func scriptRefinerContinuityContractIsVersionedAndAcceptsNewOptions() async throws {
    let registry = AgentRegistry()
    let latest = try await registry.resolve(id: "ScriptRefiner", version: nil)
    #expect(latest.version == "1.1.0")
    let previous = try await registry.resolve(id: "ScriptRefiner", version: "1.0.0")
    let inputSchema = try #require(latest.inputSchema)
    let oldInput = try #require(previous.inputSchema)
    for category in ["prop_continuity", "character_continuity", "spatial_continuity", "action_continuity"] {
        let input = JSONValue.object([
            "script": .string("Scene 1: one person holds the same key across every subscene."),
            "issues_found": .array([.object(["category": .string(category), "description": .string("Continuity contradiction.")])]),
            "correction_focus": .array([.string(category)]),
        ])
        try OutputValidator.validate(input, schema: inputSchema)
        #expect(throws: AgentError.self) { try OutputValidator.validate(input, schema: oldInput) }
        let output = JSONValue.object([
            "detected_issues": .array([.object([
                "category": .string(category), "description": .string("Points 1 and 2 conflict."),
                "correction_applied": .string("Preserve the established state."),
            ])]),
            "refined_scripts": .array([.object([
                "variation_index": .number(1), "script": .string("Consistent scene."), "notes": .string("Continuity repaired."),
            ])]),
        ])
        try OutputValidator.validate(output, schema: latest.outputSchema)
        #expect(throws: AgentError.self) { try OutputValidator.validate(output, schema: previous.outputSchema) }
    }
    // Existing callers need neither issues_found nor correction_focus.
    try OutputValidator.validate(.object(["script": .string("A coherent scene.")]), schema: inputSchema)
    for example in inputSchema["examples"]?.array ?? [] {
        try OutputValidator.validate(example, schema: inputSchema)
    }
    for example in latest.outputSchema["examples"]?.array ?? [] {
        try OutputValidator.validate(example, schema: latest.outputSchema)
    }
}
