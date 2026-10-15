#if canImport(FoundationModels) && (os(macOS) || os(iOS) || os(visionOS))
import AgentAtom
import Foundation
import FoundationModels
import Testing

@Suite(.serialized, .timeLimit(.minutes(2)), .enabled(
    if: ProcessInfo.processInfo.environment["AGENTATOM_LIVE_TESTS"] == "1",
    "Set AGENTATOM_LIVE_TESTS=1 to use the local Apple model."
))
struct AppleKeyPointsTests {
    private static var modelAvailable: Bool {
        if #available(macOS 26, iOS 26, visionOS 26, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
    }

    @Test
    func availabilityMatchesFailableInitialization() {
        if #available(macOS 26, iOS 26, visionOS 26, *) {
            let availability = SystemLanguageModel.default.availability
            print("Apple model availability: \(availability)")
            #expect((AppleIntelligenceSession() != nil) == Self.modelAvailable)
        }
    }

    @Test(.enabled(if: Self.modelAvailable, "The local Apple model is unavailable."),
          arguments: [KeyPointsSpec.namedInput, KeyPointsSpec.unnamedInput])
    func liveKeyPointsSample(input: String) async throws {
        if #available(macOS 26, iOS 26, visionOS 26, *) {
            let session = try #require(AppleIntelligenceSession(configuration: .init(
                metadata: [.duration, .modelIdentifier, .tokenUsage], temperature: 0)))
            let spec = KeyPointsSpec(input: input)
            let operation = AgenticOperation(spec: spec, session: session)
            let json = try await operation.execute().get()
            let output = try JSONDecoder().decode(KeyPointsOutput.self, from: Data(json.utf8))
            #expect(output.points.count == 3)
            #expect(Set(output.points).count == 3)
            #expect(output.points.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            #expect(output.person == (input == KeyPointsSpec.namedInput ? ["Asha", "Ben"] : []))
            #expect(await operation.spec.output == nil)
            let record = try #require(session.executionMetadata.last)
            #expect(record.operationID == operation.id)
            #expect(record.duration != nil)
            #expect(record.modelIdentifier == "SystemLanguageModel.default")
            if let count = record.promptTokens { #expect(count >= 0) }
            if let count = record.completionTokens { #expect(count >= 0) }
            print("Apple KeyPoints sample: \(json)")
        }
    }

    @Test(.enabled(if: Self.modelAvailable, "The local Apple model is unavailable."),
          arguments: [KeyPointsSpec.namedInput, "Hello.", KeyPointsSpec.insufficientInput])
    func liveFailableSample(input: String) async throws {
        if #available(macOS 26, iOS 26, visionOS 26, *) {
            let session = try #require(AppleIntelligenceSession(configuration: .init(temperature: 0)))
            let operation = FailableAgenticOperation(spec: KeyPointsSpec(input: input), session: session)
            try validate(await operation.execute(), input: input)
        }
    }

    @Test(.enabled(if: Self.modelAvailable, "The local Apple model is unavailable."))
    func liveStreamingSample() async throws {
        if #available(macOS 26, iOS 26, visionOS 26, *) {
            let session = try #require(AppleIntelligenceSession(configuration: .init(temperature: 0)))
            let operation = StreamingAgenticOperation(spec: KeyPointsSpec(input: KeyPointsSpec.unnamedInput), session: session)
            var final: Result<String, AgenticError>?
            for await snapshot in await operation.execute() { final = snapshot }
            let json = try #require(final).get()
            let output = try JSONDecoder().decode(KeyPointsOutput.self, from: Data(json.utf8))
            #expect(output.points.count == 3)
            #expect(output.person.isEmpty)
            #expect(session.executionMetadata.count == 1)
            print("Apple streaming KeyPoints sample: \(json)")
        }
    }
    @Test(.enabled(if: Self.modelAvailable, "The local Apple model is unavailable."),
          arguments: [KeyPointsSpec.namedInput, "Hello.", KeyPointsSpec.insufficientInput])
    func liveFailableStreamingSample(input: String) async throws {
        if #available(macOS 26, iOS 26, visionOS 26, *) {
            let session = try #require(AppleIntelligenceSession(configuration: .init(temperature: 0)))
            let operation = FailableStreamingAgenticOperation(spec: KeyPointsSpec(input: input), session: session)
            var final: Result<String, AgenticError>?
            for await snapshot in await operation.execute() { final = snapshot }
            try validate(#require(final), input: input)
        }
    }

    @Test(.enabled(if: Self.modelAvailable, "The local Apple model is unavailable."))
    func unsupportedSchemaFailsBeforeAdmission() async throws {
        if #available(macOS 26, iOS 26, visionOS 26, *) {
            let session = try #require(AppleIntelligenceSession())
            let operation = AgenticOperation(spec: KeyPointsSpec(input: "input"), session: session)
            let schema: JSONString = #"{"type":"string","format":"uuid"}"#
            let response = await session.respond(to: "input", instructions: "Return a UUID.", schema: schema, for: operation.id)
            #expect(response == .failure(.operationFailed(reason: "Apple guided generation does not support schema constraint: format.")))
            #expect(session.executionMetadata.isEmpty)
        }
    }

    private func validate(_ response: Result<String, AgenticError>, input: String) throws {
        if input != KeyPointsSpec.namedInput {
            guard case .failure(.generationFailed(let reason)) = response else {
                Issue.record("Expected an AI-declared failure for insufficient input, received \(response).")
                return
            }
            #expect(!reason.isEmpty)
            print("Apple KeyPoints declared failure: \(reason)")
        } else {
            let json = try response.get()
            let output = try JSONDecoder().decode(KeyPointsOutput.self, from: Data(json.utf8))
            #expect(output.points.count == 3)
            #expect(Set(output.points).count == 3)
            #expect(output.person == ["Asha", "Ben"])
            print("Apple failable KeyPoints success: \(json)")
        }
    }

}
#endif
