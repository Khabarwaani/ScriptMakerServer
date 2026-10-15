import Foundation

protocol OperationStrategy: Sendable {
    var allowsFailure: Bool { get }
    func assemble(role: String, instructions: String, schema: JSONSchema) throws(AgenticError) -> String
    func result(from response: Result<String, AgenticError>) -> Result<String, AgenticError>
}

extension OperationStrategy {
    func result(from response: Result<String, AgenticError>) -> Result<String, AgenticError> {
        guard case .success(let text) = response else { return response }
        do {
            let failure = try JSONDecoder().decode(OperationFailure.self, from: Data(text.utf8))
            guard failure.domain == "AgentAtom.Operation" else { return response }
            guard allowsFailure, failure.code == 422 else { return .failure(.operationFailed(reason: "Invalid failure response.")) }
            return .failure(.generationFailed(reason: failure.reason))
        } catch let error as AgenticError {
            return .failure(error)
        } catch {
            return response
        }
    }
}
