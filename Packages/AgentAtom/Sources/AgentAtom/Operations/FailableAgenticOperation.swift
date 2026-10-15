import Foundation

public struct FailableAgenticOperation<Specification: Spec>: AgenticOperationProtocol {
    public let spec: Specification

    public init(spec: Specification) {
        self.spec = spec
    }

    public var inputJSON: JSONString { spec.inputJSON }
    public var outputSchema: JSONSchema { Specification.outputSchema }

    public func makeInstructions() -> String {
        let success = assembleOperationInstructions(
            role: Specification.role, spec: spec.instructions, schema: outputSchema
        )
        return success + """


            If the request cannot be fulfilled, return only JSON matching this failure schema instead:
            {"type":"object","properties":{"domain":{"const":"AgentAtom.Operation"},"code":{"const":422},"reason":{"type":"string"}},"required":["domain","code","reason"],"additionalProperties":false}
            """
    }

    public func result(from response: String) throws -> Result<String, NSError> {
        let json = try? JSONSerialization.jsonObject(with: Data(response.utf8), options: [.fragmentsAllowed])
        guard let failure = json as? [String: Any], failure["domain"] as? String == "AgentAtom.Operation" else {
            return .success(response)
        }
        guard Set(failure.keys) == ["domain", "code", "reason"],
            failure["code"] as? Int == 422, let reason = failure["reason"] as? String
        else {
            throw AgenticSessionError.invalidResponse
        }
        return .failure(
            NSError(domain: "AgentAtom.Operation", code: 422, userInfo: [NSLocalizedDescriptionKey: reason]))
    }
}
