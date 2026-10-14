import Foundation
import Testing

@testable import AgentCore

@Test func scriptRefinerContinuityContractIsVersionedAndAcceptsNewOptions() async throws {
    let registry = AgentRegistry()
    let v1_1 = try await registry.resolve(id: "ScriptRefiner", version: "1.1.0")
    #expect(v1_1.version == "1.1.0")
    let v1_2 = try await registry.resolve(id: "ScriptRefiner", version: "1.2.0")
    #expect(v1_2.version == "1.2.0")

    // Legacy 1.0.0 is retired and no longer resolves
    await #expect(throws: AgentError.self) { try await registry.resolve(id: "ScriptRefiner", version: "1.0.0") }

    let inputSchema = try #require(v1_1.inputSchema)
    let v1_2Input = try #require(v1_2.inputSchema)
    for category in ["prop_continuity", "character_continuity", "spatial_continuity", "action_continuity"] {
        let input = JSONValue.object([
            "script": .string("Scene 1: one person holds the same key across every subscene."),
            "issues_found": .array([.object(["category": .string(category), "description": .string("Continuity contradiction.")])]),
            "correction_focus": .array([.string(category)]),
        ])
        try OutputValidator.validate(input, schema: inputSchema)
        try OutputValidator.validate(input, schema: v1_2Input)
        let output = JSONValue.object([
            "detected_issues": .array([.object([
                "category": .string(category), "description": .string("Points 1 and 2 conflict."),
                "correction_applied": .string("Preserve the established state."),
            ])]),
            "refined_scripts": .array([.object([
                "variation_index": .number(1), "script": .string("Consistent scene."), "notes": .string("Continuity repaired."),
            ])]),
        ])
        try OutputValidator.validate(output, schema: v1_1.outputSchema)
        // 1.2.0 requires scene_timings in output, so output without scene_timings fails 1.2.0
        #expect(throws: AgentError.self) { try OutputValidator.validate(output, schema: v1_2.outputSchema) }
    }
    // Existing callers need neither issues_found nor correction_focus.
    try OutputValidator.validate(.object(["script": .string("A coherent scene.")]), schema: inputSchema)
    for example in inputSchema["examples"]?.array ?? [] {
        try OutputValidator.validate(example, schema: inputSchema)
    }
    for example in v1_1.outputSchema["examples"]?.array ?? [] {
        try OutputValidator.validate(example, schema: v1_1.outputSchema)
    }
}

@Test func scriptRefinerTimingAndPacingContractV1_2_0() async throws {
    let registry = AgentRegistry()
    let latest = try await registry.resolve(id: "ScriptRefiner", version: nil)
    #expect(latest.version == "1.2.0")
    let v1_1 = try await registry.resolve(id: "ScriptRefiner", version: "1.1.0")

    let v1_2Input = try #require(latest.inputSchema)
    let v1_1Input = try #require(v1_1.inputSchema)

    // 1. Dialogue overflow and timing parameters are accepted in 1.2.0 and rejected by earlier versions
    let timingInput = JSONValue.object([
        "script": .string("INT. STUDIO - NIGHT\nANCHOR (speaking rapidly)\nBreaking news."),
        "scene_duration_seconds": .number(12.5),
        "scene_count": .number(2),
        "wps_range": .object([
            "min": .number(2.0),
            "max": .number(3.5),
        ]),
        "issues_found": .array([.object([
            "category": .string("dialogue_overflow"),
            "description": .string("Dialogue duration exceeds scene duration."),
        ])]),
        "correction_focus": .array([.string("dialogue_overflow")]),
    ])
    try OutputValidator.validate(timingInput, schema: v1_2Input)
    #expect(throws: AgentError.self) { try OutputValidator.validate(timingInput, schema: v1_1Input) }

    // 2. Scene timing breakdown in output is required and validated in 1.2.0
    let v1_2Output = JSONValue.object([
        "detected_issues": .array([.object([
            "category": .string("dialogue_overflow"),
            "description": .string("Anchor speech exceeds 10s scene limit."),
            "correction_applied": .string("Split across 2 scenes with tightened dialogue."),
        ])]),
        "refined_scripts": .array([.object([
            "variation_index": .number(1),
            "script": .string("SCENE 1:\nANCHOR\nBreaking news.\nSCENE 2:\nANCHOR\nMore details."),
            "notes": .string("Tightened dialogue and split across 2 scenes."),
            "scene_timings": .array([
                .object([
                    "scene_number": .number(1),
                    "dialogue_duration_seconds": .number(4.5),
                    "non_dialogue_duration_seconds": .number(5.5),
                    "total_duration_seconds": .number(10.0),
                ]),
                .object([
                    "scene_number": .number(2),
                    "dialogue_duration_seconds": .number(3.0),
                    "non_dialogue_duration_seconds": .number(6.0),
                    "total_duration_seconds": .number(9.0),
                ]),
            ]),
        ])]),
    ])
    try OutputValidator.validate(v1_2Output, schema: latest.outputSchema)
    #expect(throws: AgentError.self) { try OutputValidator.validate(v1_2Output, schema: v1_1.outputSchema) }

    // 3. Output missing scene_timings is rejected by 1.2.0
    let missingTimingsOutput = JSONValue.object([
        "detected_issues": .array([.object([
            "category": .string("dialogue_overflow"),
            "description": .string("Overflow detected."),
            "correction_applied": .string("Repaired."),
        ])]),
        "refined_scripts": .array([.object([
            "variation_index": .number(1),
            "script": .string("Some script."),
            "notes": .string("Notes without timing breakdown."),
        ])]),
    ])
    #expect(throws: AgentError.self) { try OutputValidator.validate(missingTimingsOutput, schema: latest.outputSchema) }

    // 4. Backward compatibility: minimal input with only script is accepted across all versions
    let minimalInput = JSONValue.object(["script": .string("INT. ROOM - DAY\nPerson speaks.")])
    try OutputValidator.validate(minimalInput, schema: v1_2Input)
    try OutputValidator.validate(minimalInput, schema: v1_1Input)

    // 5. Schema example validation
    for example in v1_2Input["examples"]?.array ?? [] {
        try OutputValidator.validate(example, schema: v1_2Input)
    }
    for example in latest.outputSchema["examples"]?.array ?? [] {
        try OutputValidator.validate(example, schema: latest.outputSchema)
    }
}

