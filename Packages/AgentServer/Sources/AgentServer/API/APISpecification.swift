import AgentCore
import Foundation

/// One operation catalog drives route paths, the OpenAPI document and browser docs.
enum APIOperation: String, CaseIterable {
    case listAgents, executeAgent, getStatus, cancelExecution, getSpecification, getExecutionLogs, downloadExecutionLog
    var path: String {
        switch self {
        case .listAgents: "/agents"
        case .executeAgent: "/execute"
        case .getStatus: "/status"
        case .cancelExecution: "/executions/{execution_id}/cancel"
        case .getSpecification: "/openapi.json"
        case .getExecutionLogs: "/execution-logs"
        case .downloadExecutionLog: "/execution-logs/download"
        }
    }
    var method: String { self == .executeAgent || self == .cancelExecution ? "post" : "get" }
    var summary: String {
        switch self {
        case .listAgents: "List agent IDs, names and available versions"
        case .executeAgent: "Execute an agent and return its validated result"
        case .getStatus: "Read health and tracked execution states"
        case .cancelExecution: "Cancel a specific execution"
        case .getSpecification: "Read the current OpenAPI specification"
        case .getExecutionLogs: "Read recent session execution logs"
        case .downloadExecutionLog: "Download the complete session execution log"
        }
    }
    var explanation: String {
        switch self {
        case .listAgents:
            "Returns only the agents list, with id, name and available versions for each valid registered agent. Agent contracts, documentation and provider metadata are available from /openapi.json."
        case .executeAgent:
            "Returns one final schema-validated JSON value or a structured error by default (status=false, which may be omitted). Add ?status=true for SSE status/progress updates and one validated result or terminal error. Provisional provider output is never returned. Supply agent_id, provider and a JSON input object; omit version for the highest stable version. X-Execution-ID identifies accepted work; in final-only mode the header arrives with the final response."
        case .getStatus:
            "Returns a snapshot, not an output stream. States include queued, running, cancelling, cancelled, completed and failed. started_at is acceptance time; running_at is when queued work begins running. elapsed_seconds excludes queue time and freezes at ended_at for terminal states. Tracking is in memory for this server session only and is purged on shutdown. Terminal records retain execution_id, status, timing and a bounded error code/message when failed; execution resources, prompts and results are not retained."
        case .cancelExecution:
            "Requests cancellation only for this execution. Repeated requests are safe. A running execution remains cancelling until its provider process stops. Unknown IDs return a structured 404 error."
        case .getSpecification:
            "Returns this live OpenAPI 3.1 document. Agent schemas and examples reflect the current registry. Clients can use this endpoint to discover request and response contracts."
        case .getExecutionLogs:
            "Returns the latest 200 execution state snapshots from the temporary JSONL session log, oldest first. Includes IDs, states, timing and bounded error details, without prompts or provider output. A fresh server start clears the file. Open /logs from Help to view details."
        case .downloadExecutionLog:
            "Streams the complete session log as newline-delimited JSON in bounded chunks. Includes accepted executions and their state transitions and outcomes. Download is a fixed snapshot; a fresh server start clears the log."
        }
    }
}

enum APISpecification {
    private static func object(_ fields: [String: JSONValue], required: [String] = []) -> JSONValue {
        .object([
            "type": .string("object"), "properties": .object(fields),
            "required": .array(required.map(JSONValue.string)),
        ])
    }
    private static let string = JSONValue.object(["type": .string("string")])
    private static let integer = JSONValue.object(["type": .string("integer")])
    private static let boolean = JSONValue.object(["type": .string("boolean")])
    private static func array(_ items: JSONValue) -> JSONValue {
        .object(["type": .string("array"), "items": items])
    }
    private static func reference(_ name: String) -> JSONValue {
        .object(["$ref": .string("#/components/schemas/" + name)])
    }

    static func document(agents: [AgentSummary], providers: [ProviderStatus]) throws -> JSONValue {
        let encoder = JSONEncoder()
        let catalog = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(agents))
        let providerCatalog = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(providers))
        let defaultAgent = agents.first
        let defaultDefinition =
            defaultAgent?.definitions.first(where: { $0.version == defaultAgent?.latest })
            ?? defaultAgent?.definitions.first
        let inputExample = defaultDefinition?.input_schema?["examples"]?.array?.first ?? .object([:])
        var requestExample: [String: JSONValue] = [
            "agent_id": .string(defaultAgent?.id ?? "AgentID"),
            "provider": .string(providers.first?.id ?? "codex"), "input": inputExample,
        ]
        if let version = defaultAgent?.latest { requestExample["version"] = .string(version) }
        let error = object(
            ["code": string, "message": string, "execution_id": string], required: ["code", "message"])
        let execution = object(
            [
                "execution_id": string, "agent_id": string, "version": string, "provider": string,
                "status": .object([
                    "type": .string("string"),
                    "enum": .array(
                        ["queued", "running", "cancelling", "cancelled", "completed", "failed"].map(
                            JSONValue.string)),
                ]),
                "streaming": boolean,
                "started_at": .object([
                    "type": .string("string"), "format": .string("date-time"),
                    "description": .string("Time the execution was accepted, including queued work."),
                ]),
                "running_at": .object([
                    "type": .string("string"), "format": .string("date-time"),
                    "description": .string("Time execution began running; absent if it never ran."),
                ]),
                "ended_at": .object(["type": .string("string"), "format": .string("date-time")]),
                "elapsed_seconds": .object([
                    "type": .string("number"), "minimum": .number(0),
                    "description": .string("Running duration excluding queue time. Zero before running; fixed after termination."),
                ]),
                "schema_validated": boolean, "error": reference("Error"), "process_id": integer,
                "resident_memory_bytes": integer,
            ],
            required: [
                "execution_id", "status", "started_at",
                "elapsed_seconds",
            ])
        let agent = JSONValue.object([
            "type": .string("object"),
            "properties": .object(["id": string, "name": string, "versions": array(string)]),
            "required": .array(["id", "name", "versions"].map(JSONValue.string)),
            "additionalProperties": .bool(false),
        ])
        let provider = object(
            ["id": string, "available": boolean, "readiness": string],
            required: ["id", "available", "readiness"])
        let status = object(
            [
                "status": string,
                "server": object(
                    ["version": string, "uptime_seconds": integer], required: ["version", "uptime_seconds"]),
                "active_executions": integer, "queued_executions": integer,
                "provider_resident_memory_bytes": integer,
                "system_resources": object([
                    "physical_memory_bytes": integer, "available_memory_bytes": integer,
                    "load_average": .object(["type": .string("number")]), "cpu_count": integer,
                ]),
                "executions": array(reference("ExecutionRecord")), "providers": array(provider),
            ], required: ["status", "server", "active_executions", "queued_executions", "executions"])
        let request = object(
            [
                "agent_id": string, "version": string,
                "provider": .object([
                    "type": .string("string"), "enum": .array(providers.map { .string($0.id) }),
                ]),
                "input": .object([
                    "type": .string("object"),
                    "description": .string(
                        "Agent-specific input. See x-agents for the exact version's schema."),
                ]),
            ], required: ["agent_id", "provider", "input"])
        let cancel = object(
            ["execution_id": string, "status": string], required: ["execution_id", "status"])
        var schemas: [String: JSONValue] = [
            "Error": error, "ErrorResponse": object(["error": reference("Error")], required: ["error"]),
            "ExecuteRequest": request, "ExecutionRecord": execution, "StatusResponse": status,
            "AgentsResponse": .object([
                "type": .string("object"), "properties": .object(["agents": array(agent)]),
                "required": .array([.string("agents")]), "additionalProperties": .bool(false),
            ]),
            "CancelResponse": cancel,
        ]
        for agent in agents {
            for definition in agent.definitions {
                let name =
                    agent.id + "_"
                    + definition.version.replacingOccurrences(of: ".", with: "_").replacingOccurrences(
                        of: "+", with: "_")
                schemas[name + "_Output"] = definition.output_schema
                if let input = definition.input_schema { schemas[name + "_Input"] = input }
            }
        }
        var paths: [String: JSONValue] = [:]
        let outputSchemas = agents.flatMap { agent in
            agent.definitions.map { definition in
                reference(agent.id + "_" + definition.version.replacingOccurrences(of: ".", with: "_")
                    .replacingOccurrences(of: "+", with: "_") + "_Output")
            }
        }
        for operation in APIOperation.allCases {
            let responseSchema: JSONValue =
                switch operation {
                case .listAgents: reference("AgentsResponse")
                case .executeAgent:
                    .object([
                        "anyOf": .array(outputSchemas.isEmpty ? [.bool(true)] : outputSchemas),
                        "description": .string(
                            "The validated final value matching the selected agent version's output schema."
                        ),
                    ])
                case .getStatus: reference("StatusResponse")
                case .cancelExecution: reference("CancelResponse")
                case .getSpecification: .object(["type": .string("object")])
                case .getExecutionLogs: object(["entries": array(reference("ExecutionRecord"))], required: ["entries"])
                case .downloadExecutionLog: .object(["type": .string("string")])
                }
            let responseType = operation == .downloadExecutionLog ? "application/x-ndjson" : "application/json"
            var entry: [String: JSONValue] = [
                "operationId": .string(operation.rawValue), "summary": .string(operation.summary),
                "description": .string(operation.explanation),
                "responses": .object([
                    "200": .object([
                        "description": .string("Success"),
                        "content": .object([responseType: .object(["schema": responseSchema])]),
                    ]),
                    "400": errorResponse("Invalid request"),
                    "404": errorResponse("Unknown agent, version, execution or endpoint"),
                    "503": errorResponse("Unavailable provider, resource pressure or server shutdown"),
                    "500": errorResponse("Execution or internal failure"),
                ]),
            ]
            if operation == .executeAgent {
                entry["parameters"] = .array([.object([
                    "name": .string("status"), "in": .string("query"), "required": .bool(false),
                    "schema": .object(["type": .string("boolean"), "default": .bool(false)]),
                    "description": .string("Omit or set false for one final JSON response. Set true for SSE status updates and the validated final result. No raw provider output is exposed."),
                ])])
                entry["requestBody"] = .object([
                    "required": .bool(true),
                    "content": .object([
                        "application/json": .object([
                            "schema": reference("ExecuteRequest"), "example": .object(requestExample),
                        ])
                    ]),
                ])
                var responses = entry["responses"]!.object!
                var success = responses["200"]!.object!
                var content = success["content"]!.object!
                content["text/event-stream"] = .object([
                    "schema": .object([
                        "type": .string("string"),
                        "description": .string("Only when status=true: ordered started/status/result/completed or failed/cancelled SSE events. See x-stream-events."),
                    ])
                ])
                success["content"] = .object(content)
                success["headers"] = .object([
                    "X-Execution-ID": .object([
                        "description": .string("Assigned execution ID"), "schema": string,
                    ])
                ])
                responses["200"] = .object(success)
                entry["responses"] = .object(responses)
            }
            if operation == .cancelExecution {
                entry["parameters"] = .array([
                    .object([
                        "name": .string("execution_id"), "in": .string("path"), "required": .bool(true),
                        "schema": string,
                    ])
                ])
            }
            paths[operation.path] = .object([operation.method: .object(entry)])
        }
        return .object([
            "openapi": .string("3.1.0"),
            "info": .object(["title": .string("AgentServer HTTP API"), "version": .string("1.1.0")]),
            "servers": .array([.object(["url": .string("/")])]), "paths": .object(paths),
            "components": .object(["schemas": .object(schemas)]), "x-agents": catalog,
            "x-providers": providerCatalog,
            "x-operation-order": .array(APIOperation.allCases.map { .string($0.rawValue) }),
            "x-stream-events": .array([
                .object([
                    "name": .string("started"),
                    "description": .string(
                        "Execution accepted; includes ID, agent, resolved version, provider, started_at and elapsed_seconds. Every event includes timing metadata; running_at and ended_at appear when available."),
                ]),
                .object([
                    "name": .string("status"),
                    "description": .string(
                        "State, periodic heartbeat or provider progress. A heartbeat alone does not prove model progress."
                    ),
                ]),
                .object([
                    "name": .string("result"),
                    "description": .string(
                        "Final parsed JSON that passed the selected agent's output schema."),
                ]),
                .object([
                    "name": .string("completed"),
                    "description": .string("Successful terminal state, emitted after result."),
                ]),
                .object([
                    "name": .string("failed"),
                    "description": .string("Structured error; no successful completion."),
                ]),
                .object([
                    "name": .string("cancelled"),
                    "description": .string("Scoped cancellation confirmed; stream closes."),
                ]),
            ]),
        ])
    }
    private static func errorResponse(_ description: String) -> JSONValue {
        .object([
            "description": .string(description),
            "content": .object(["application/json": .object(["schema": reference("ErrorResponse")])]),
        ])
    }
}
