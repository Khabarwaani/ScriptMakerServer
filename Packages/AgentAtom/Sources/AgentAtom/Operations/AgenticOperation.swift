public struct AgenticOperation<Specification: Spec>: AgenticOperationProtocol {
    public let spec: Specification

    public init(spec: Specification) {
        self.spec = spec
    }

    public var inputJSON: JSONString { spec.inputJSON }
    public var outputSchema: JSONSchema { Specification.outputSchema }

    public func makeInstructions() -> String {
        assembleOperationInstructions(
            role: Specification.role, spec: spec.instructions, schema: outputSchema
        )
    }
}
