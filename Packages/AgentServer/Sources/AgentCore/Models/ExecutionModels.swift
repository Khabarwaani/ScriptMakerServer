import Foundation

public struct ExecuteRequest: Codable, Sendable {
    public let agent_id: String
    public let version: String?
    public let provider: String
    public let input: JSONValue
    public init(agentID: String, version: String? = nil, provider: String, input: JSONValue) {
        self.agent_id = agentID; self.version = version; self.provider = provider; self.input = input
    }
}

public struct StreamEvent: Sendable {
    public let name: String
    public let data: JSONValue
    public func sse() throws -> String { "event: \(name)\ndata: \(try data.text())\n\n" }
}

public struct ExecutionRecord: Codable, Sendable {
    public let execution_id: String
    public let agent_id: String
    public let version: String
    public let provider: String
    public var status: String
    public var streaming: Bool
    public let started_at: Date
    public var ended_at: Date?
    public var error: AgentError?
    public var schema_validated: Bool?
    public var process_id: Int32?
    public var resident_memory_bytes: UInt64
}

public struct AcceptedExecution: Sendable {
    public let id: String
    public let events: AsyncStream<StreamEvent>
}

public struct ExecutionSnapshot: Sendable {
    public let records: [ExecutionRecord]
    public let activeCount: Int
    public let queuedCount: Int
    public let residentMemoryBytes: UInt64
    public let accepting: Bool
}

