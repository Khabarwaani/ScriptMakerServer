public struct FailableAgenticOperation<Specification: Spec>: AgenticOperationProtocol {
    public let spec: Specification

    public init(spec: Specification) {
        self.spec = spec
    }

    public func makeInstructions() -> String {
        OperationInstructionAssembler(strategy: FailableInstructionStrategy()).assemble(spec: spec)
    }
}
