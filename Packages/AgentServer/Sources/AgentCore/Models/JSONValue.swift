@_exported import AgentCoreBase
import Foundation

public struct AgentError: Error, Codable, Sendable, Equatable {
    public let code: String
    public let message: String
    public var execution_id: String?
    public let details: JSONValue?
    public init(_ code: String, _ message: String, executionID: String? = nil, details: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.execution_id = executionID
        self.details = details
    }
    public var httpStatus: Int {
        switch code {
        case "unknown_agent", "unknown_version", "unknown_execution": 404
        case "invalid_request", "invalid_json", "input_schema_validation_failed", "invalid_agent_definition": 400
        case "input_not_feasible": 422
        case "provider_unavailable", "provider_initialization_failed", "server_shutting_down",
            "resource_pressure", "execution_log_unavailable":
            503
        case "unsupported_provider": 400
        default: 500
        }
    }
}
