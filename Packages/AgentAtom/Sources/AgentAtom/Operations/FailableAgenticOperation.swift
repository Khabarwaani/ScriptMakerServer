public struct FailableAgenticOperation<Specification: Spec>: AgenticOperationProtocol {
    public let spec: Specification

    public init(spec: Specification) {
        self.spec = spec
    }

    public func makeInstructions() -> String {
        let success = assembleOperationInstructions(
            role: Specification.role, spec: spec.instructions, schema: Specification.outputSchema
        )
        return success + """


            If the request cannot be fulfilled, return only JSON matching this failure schema instead:
            {"type":"object","properties":{"domain":{"const":"AgentAtom.Operation"},"code":{"const":422},"reason":{"type":"string"}},"required":["domain","code","reason"],"additionalProperties":false}
            """
    }
}
