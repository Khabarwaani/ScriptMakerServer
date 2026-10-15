public protocol AgenticOperationProtocol: Sendable {
    associatedtype Specification: Spec
    var spec: Specification { get }
    func makeInstructions() throws -> String
}
