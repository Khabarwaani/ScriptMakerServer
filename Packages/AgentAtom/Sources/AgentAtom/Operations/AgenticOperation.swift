import Foundation

/// A value describing one request. Callers own reference-backed input stability.
public protocol AgenticOperationProtocol: Sendable {
    associatedtype Output: Sendable
    func makeRequest() throws -> AgenticRequest
    func decode(_ content: AgenticContent) throws -> Output
}

public struct AgenticOperation<Specification: ModelledSpec>: AgenticOperationProtocol {
    public let spec: Specification
    public let instructions: String?

    public init(spec: Specification, instructions: String? = nil) {
        self.spec = spec
        self.instructions = instructions
    }

    public func makeRequest() throws -> AgenticRequest {
        AgenticRequest(
            input: .json(spec.inputJSON), output: .json(Specification.outputSchema),
            instructions: instructions, role: Specification.role, specInstructions: spec.instructions
        )
    }

    public func decode(_ content: AgenticContent) throws -> Specification.Output {
        try decode(content, decoder: JSONDecoder())
    }

    public func decode(_ content: AgenticContent, decoder: JSONDecoder) throws -> Specification.Output {
        try decoder.decode(Specification.Output.self, from: content.jsonData())
    }
}

public struct FailableAgenticOperation<Specification: ModelledSpec>: AgenticOperationProtocol {
    public let spec: Specification
    public let instructions: String?
    public let failureGuidance: String?

    public init(spec: Specification, instructions: String? = nil, failureGuidance: String? = nil) {
        self.spec = spec
        self.instructions = instructions
        self.failureGuidance = failureGuidance
    }

    public func makeRequest() throws -> AgenticRequest {
        let schema = try JSONSchema.failable(success: Specification.outputSchema)
        let guidance = """
            Return either {"status":"success","output":<requested output>} or
            {"status":"failure","failure":{"reason":"<reason>"}}.
            If you cannot fulfill the request, return the failure outcome. Do not invent an answer.
            """
        return AgenticRequest(
            input: .json(spec.inputJSON), output: .json(schema),
            instructions: [instructions, guidance, failureGuidance].compactMap { $0 }.joined(separator: "\n"),
            role: Specification.role, specInstructions: spec.instructions
        )
    }

    public func decode(_ content: AgenticContent) throws -> AgenticResult<Specification.Output> {
        try decode(content, decoder: JSONDecoder())
    }

    /// Decoder strategies apply to domain output, never reserved envelope keys.
    public func decode(_ content: AgenticContent, decoder: JSONDecoder) throws -> AgenticResult<Specification.Output> {
        let envelope = try JSONDecoder().decode(AgenticEnvelope.self, from: content.jsonData())
        switch envelope {
        case .success(let value):
            return .success(try decoder.decode(Specification.Output.self, from: JSONEncoder().encode(value)))
        case .failure(let failure):
            return .failure(failure)
        }
    }
}

extension JSONSchema {
    static func failable(success: JSONSchema) throws -> JSONSchema {
        try JSONSchema(
            node: .union([
                .object(
                    ["status": .choices(["success"]), "output": success.node],
                    required: ["status", "output"], closed: true),
                .object(
                    [
                        "status": .choices(["failure"]),
                        "failure": .object(["reason": .scalar("string")], required: ["reason"], closed: true),
                    ],
                    required: ["status", "failure"], closed: true),
            ]))
    }
}
