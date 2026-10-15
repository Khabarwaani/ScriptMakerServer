import Foundation

protocol OperationStrategy: Sendable {
    var allowsFailure: Bool { get }
    func assemble(role: String, instructions: String, schema: JSONSchema) throws(AgenticError) -> String
    func result(from response: Result<String, AgenticError>) -> Result<String, AgenticError>
}

extension OperationStrategy {
    func schema(for output: JSONSchema) throws(AgenticError) -> JSONString {
        do {
            var object = try JSONSerialization.jsonObject(with: Data(output.rawValue.utf8))
            if allowsFailure {
                guard let failureSchema = JSONSchema(OperationFailure.self),
                      var failure = try JSONSerialization.jsonObject(with: Data(failureSchema.rawValue.utf8)) as? [String: Any],
                      var properties = failure["properties"] as? [String: Any] else {
                    throw AgenticError.operationFailed(reason: "The failure schema could not be derived.")
                }
                guard var success = object as? [String: Any] else {
                    throw AgenticError.operationFailed(reason: "Invalid success schema.")
                }
                success["title"] = "Success"
                success["description"] = "A completed response satisfying every spec requirement, including requested counts."
                failure["title"] = "Failure"
                failure["description"] = "The input is insufficient to satisfy a spec requirement, such as a requested count, without inventing facts."
                properties["domain"] = ["type": "string", "enum": ["AgentAtom.Operation"]]
                properties["code"] = ["type": "integer", "minimum": 422, "maximum": 422]
                failure["properties"] = properties
                object = ["anyOf": [success, failure]]
            }
            let data = try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed, .sortedKeys])
            guard let schema = JSONString(String(decoding: data, as: UTF8.self)) else {
                throw AgenticError.operationFailed(reason: "Invalid response schema.")
            }
            return schema
        } catch {
            throw (error as? AgenticError) ?? .operationFailed(reason: error.localizedDescription)
        }
    }

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
