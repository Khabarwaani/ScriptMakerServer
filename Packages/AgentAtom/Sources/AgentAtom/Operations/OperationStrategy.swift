import Foundation

protocol OperationStrategy: Sendable {
    var allowsFailure: Bool { get }
    func assemble(role: String, instructions: String, schema: JSONSchema) throws(AgenticError) -> String
    func result(from response: Result<String, AgenticError>) -> Result<String, AgenticError>
}

extension OperationStrategy {
    func result(from response: Result<String, AgenticError>) -> Result<String, AgenticError> {
        guard case .success(let text) = response else { return response }
        let data = Data(text.utf8)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["domain"] as? String == "AgentAtom.Operation" else {
            return response
        }
        guard allowsFailure,
              let failure = try? JSONDecoder().decode(OperationFailure.self, from: data),
              failure.code == 422 else {
            return .failure(.operationFailed)
        }
        return .failure(.generationFailed(reason: failure.reason))
    }
}
