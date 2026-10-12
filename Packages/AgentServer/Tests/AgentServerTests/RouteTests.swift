import AgentCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing

@testable import AgentServer

private struct RouteProvider: AIProvider {
    let id = "mock"
    func checkReadiness() async throws {}
    func execute(
        definition: AgentDefinition, input: JSONValue, runner: ProcessRunner, directory: URL,
        timeoutSeconds: Int, onOutput: @escaping @Sendable (String) async -> Void,
        onProgress: @escaping @Sendable (JSONValue) async -> Void
    ) async throws -> JSONValue {
        await onOutput("partial")
        return .object(["result": input["text"] ?? .string("hello")])
    }
}

@Test func httpContractsAndStructuredErrors() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try AgentPackageTools.create(id: "Echo", root: root.appendingPathComponent("Agents", isDirectory: true))
    let registry = AgentRegistry(root: root.appendingPathComponent("Agents"))
    let providers = ProviderCatalog(providers: [RouteProvider()])
    let manager = ExecutionManager(
        registry: registry, providers: providers, runtimeRoot: root.appendingPathComponent("Runtime"),
        resourceSample: {
            SystemResources(
                physical_memory_bytes: 8_589_934_592, available_memory_bytes: 4_294_967_296, load_average: 0,
                cpu_count: 8)
        })
    let app = Application(
        router: ServerRoutes.makeRouter(registry: registry, providers: providers, manager: manager))
    try await app.test(.router) { client in
        try await client.execute(uri: "/agents", method: .get) { response in
            #expect(response.status == .ok)
            let value = try JSONValue.parse(String(buffer: response.body))
            #expect(value["agents"]?.array?.first?["id"] == .string("Echo"))
            #expect(value["agents"]?.array?.first?["definitions"]?.array?.first?["output_schema"] != nil)
        }
        try await client.execute(
            uri: "/execute", method: .post, headers: [.contentType: "application/json"],
            body: .init(string: "{}")
        ) { response in
            #expect(response.status == .badRequest)
            let value = try JSONValue.parse(String(buffer: response.body))
            #expect(value["error"]?["code"] == .string("invalid_request"))
        }
        try await client.execute(
            uri: "/execute", method: .post, headers: [.contentType: "application/json"],
            body: .init(string: "{")
        ) { response in
            #expect(response.status == .badRequest)
        }
        try await client.execute(
            uri: "/execute", method: .post, headers: [.contentType: "application/json"],
            body: .init(string: #"{"agent_id":"Echo","provider":"mock","input":{"text":"hello"}}"#)
        ) { response in
            #expect(response.status == .ok)
            #expect(response.headers[.contentType] == "text/event-stream")
            #expect(response.headers[.init("X-Execution-ID")!] != nil)
            let text = String(buffer: response.body)
            #expect(text.contains("event: output\n"))
            #expect(text.contains("event: result\n"))
            #expect(text.contains("event: completed\n"))
        }
        try await client.execute(uri: "/status", method: .get) { response in
            let value = try JSONValue.parse(String(buffer: response.body))
            #expect(value["status"] == .string("healthy"))
            #expect(value["executions"]?.array?.first?["status"] == .string("completed"))
        }
        try await client.execute(uri: "/executions/missing/cancel", method: .post) { response in
            #expect(response.status == .notFound)
            let value = try JSONValue.parse(String(buffer: response.body))
            #expect(value["error"]?["code"] == .string("unknown_execution"))
        }
        try await client.execute(uri: "/help", method: .get) { response in
            #expect(response.status == .ok)
            let html = String(buffer: response.body)
            #expect(html.contains("HTTP API reference"))
            #expect(!html.contains("swift run"))
            #expect(html.contains("/try?operation="))
        }
        try await client.execute(uri: "/openapi.json", method: .get) { response in
            #expect(response.status == .ok)
            let document = try JSONValue.parse(String(buffer: response.body))
            #expect(document["openapi"] == .string("3.1.0"))
            #expect(document["paths"]?["/execute"]?["post"]?["operationId"] == .string("executeAgent"))
            #expect(document["paths"]?["/executions/{execution_id}/cancel"] != nil)
            #expect(document["x-agents"]?.array?.first?["id"] == .string("Echo"))
        }
        try await client.execute(uri: "/try?operation=getStatus", method: .get) { response in
            #expect(response.status == .ok)
            #expect(String(buffer: response.body).contains("Send request"))
        }
        try await client.execute(uri: "/unknown", method: .get) { response in
            #expect(response.status == .notFound)
            let value = try JSONValue.parse(String(buffer: response.body))
            #expect(value["error"]?["code"] == .string("unknown_endpoint"))
        }
    }
}
