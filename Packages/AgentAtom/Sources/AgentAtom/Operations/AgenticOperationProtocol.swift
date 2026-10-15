public protocol AgenticOperationProtocol: Identifiable, Sendable where ID == ObjectIdentifier {
    associatedtype Specification: Spec
    associatedtype Result: Sendable

    var spec: Specification { get async }
    var state: OperationState { get async }

    func instructions() async throws(AgenticError) -> String
    func execute() async -> Result
    func cancel() async
    func pause() async throws(AgenticError)
    func resume() async throws(AgenticError)
}
