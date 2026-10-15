public struct AgenticOperation<Specification: Spec>: AgenticOperationProtocol {
    public let spec: Specification
    public let baseInstructions: String?
    public let operationInstructions: String?

    public init(spec: Specification, baseInstructions: String? = nil, instructions: String? = nil) {
        self.spec = spec
        self.baseInstructions = baseInstructions
        self.operationInstructions = instructions
    }

    public var inputJSON: JSONString { spec.inputJSON }
    public var outputSchema: JSONSchema { Specification.outputSchema }

    public var instructions: String {
        assembleOperationInstructions(
            base: baseInstructions, operation: operationInstructions,
            role: Specification.role, spec: spec.instructions, schema: outputSchema
        )
    }
}
