@testable import AgentAtom
import Foundation
import Testing

struct InstructionFailureTests {
    @Test
    func failureSchemaHasRequiredWireFields() throws {
        let schema = try #require(JSONSchema(OperationFailure.self))
        let object = try #require(JSONSerialization.jsonObject(with: Data(schema.rawValue.utf8)) as? [String: Any])
        let properties = try #require(object["properties"] as? [String: Any])
        #expect(Set(properties.keys) == ["domain", "code", "reason"])
        #expect(Set(object["required"] as? [String] ?? []) == ["domain", "code", "reason"])
        #expect((properties["domain"] as? [String: Any])?["type"] as? String == "string")
        #expect((properties["code"] as? [String: Any])?["type"] as? String == "integer")
        #expect((properties["reason"] as? [String: Any])?["type"] as? String == "string")
    }

    @Test
    func assemblyFailureDoesNotAdmitSessionRun() async {
        let session = TestSession()
        let operation = RejectingOperation(session: session)
        #expect(await operation.execute() == .failure(.operationFailed(reason: "Assembly failed.")))
        #expect(await operation.state == .failed)
        #expect(session.requests.isEmpty)
        #expect(session.executionMetadata.isEmpty)
        let next = AgenticOperation(spec: KeyPointsSpec(input: "input"), session: session)
        #expect(await next.execute() == .success(KeyPointsSpec.namedJSON))
    }
}

private struct RejectingStrategy: OperationStrategy {
    let allowsFailure = false
    func assemble(role: String, instructions: String, schema: JSONSchema) throws(AgenticError) -> String {
        throw .operationFailed(reason: "Assembly failed.")
    }
}

private actor RejectingOperation: AgenticOperationProtocol, OperationLifecycle {
    typealias Result = Swift.Result<String, AgenticError>
    let spec = KeyPointsSpec(input: "input")
    let session: TestSession
    let strategy = RejectingStrategy()
    var state: OperationState = .ready
    var task: Task<Result, Never>?

    init(session: TestSession) { self.session = session }
    func execute() async -> Result { await start() }
}
