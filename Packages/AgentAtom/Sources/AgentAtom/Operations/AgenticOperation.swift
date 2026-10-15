public struct AgenticOperation<Specification: Spec>: AgenticOperationProtocol {
    public let spec: Specification

    public init(spec: Specification) {
        self.spec = spec
    }

    public func makeInstructions() -> String {
        OperationInstructionAssembler(strategy: JSONInstructionStrategy()).assemble(spec: spec)
    }
}
