import AgentCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing

@testable import AgentServer

private actor ReadinessTracker {
    var count = 0
    func recordCheck() { count += 1 }
}

private struct RouteProvider: AIProvider {
    enum Outcome: String, Sendable { case success, schemaFailure, providerFailure, cancelled }
    let id = "mock"
    let readiness = ReadinessTracker()
    var outcome: Outcome = .success
    func checkReadiness() async throws { await readiness.recordCheck() }
    func execute(
        definition: AgentDefinition, input: JSONValue, runner: ProcessRunner, directory: URL,
        timeoutSeconds: Int, onOutput: @escaping @Sendable (String) async -> Void,
        onProgress: @escaping @Sendable (JSONValue) async -> Void
    ) async throws -> JSONValue {
        await onOutput("partial")
        await onProgress(.object(["message": .string("Working")]))
        switch outcome {
        case .schemaFailure: return .object(["result": .number(123)])
        case .providerFailure: throw AgentError("provider_execution_failed", "Mock execution failed.")
        case .cancelled: throw CancellationError()
        case .success: break
        }
        return .object(["result": input["text"] ?? .string("hello")])
    }
}

private enum RouteEchoPackage: AgentPackageContract {
    static let id = "Echo"
    static let name = "Echo Agent"
    static let versions = ["1.0.0"]
    nonisolated(unsafe) static var rootURL: URL?
    static func directory(version: String) throws -> URL {
        guard let rootURL, versions.contains(version) else { throw AgentError("unknown_version", "Version unavailable.") }
        return rootURL.appendingPathComponent("Echo/\(version)")
    }
    static func role(version: String) throws -> String {
        try String(contentsOf: directory(version: version).appendingPathComponent("role.md"), encoding: .utf8)
    }
    static func instructions(version: String) throws -> String {
        try String(contentsOf: directory(version: version).appendingPathComponent("instructions.md"), encoding: .utf8)
    }
    static func outputSchema(version: String) throws -> String {
        try String(contentsOf: directory(version: version).appendingPathComponent("output.schema.json"), encoding: .utf8)
    }
    static func inputSchema(version: String) throws -> String? {
        let file = try directory(version: version).appendingPathComponent("input.schema.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try String(contentsOf: file, encoding: .utf8)
    }
}

@Test func httpContractsAndStructuredErrors() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try AgentPackageTools.create(id: "Echo", root: root.appendingPathComponent("Agents", isDirectory: true))
    try AgentPackageTools.create(id: "UnregisteredOnDisk", root: root.appendingPathComponent("Agents", isDirectory: true))
    RouteEchoPackage.rootURL = root.appendingPathComponent("Agents")
    let registry = AgentRegistry(packages: [RouteEchoPackage.self], root: root.appendingPathComponent("Agents"))
    let provider = RouteProvider()
    let providers = ProviderCatalog(providers: [provider])
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
            #expect(value == .object([
                "agents": .array([.object([
                    "id": .string("Echo"), "name": .string("Echo Agent"),
                    "versions": .array([.string("1.0.0")]),
                ])]),
            ]))
            #expect(await provider.readiness.count == 0)
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
            body: .init(string: #"{"agent_id":"UnregisteredOnDisk","provider":"mock","input":{"text":"hello"}}"#)
        ) { response in
            #expect(response.status == .badRequest)
            let value = try JSONValue.parse(String(buffer: response.body))
            #expect(value["error"]?["code"] == .string("invalid_agent_definition"))
        }
        try await client.execute(
            uri: "/execute", method: .post, headers: [.contentType: "application/json"],
            body: .init(string: #"{"agent_id":"Nonexistent","provider":"mock","input":{"text":"hello"}}"#)
        ) { response in
            #expect(response.status == .notFound)
            let value = try JSONValue.parse(String(buffer: response.body))
            #expect(value["error"]?["code"] == .string("unknown_agent"))
        }
        try await client.execute(
            uri: "/execute?status=true", method: .post, headers: [.contentType: "application/json"],
            body: .init(string: #"{"agent_id":"Echo","provider":"mock","input":{"text":"hello"}}"#)
        ) { response in
            #expect(response.status == .ok)
            #expect(response.headers[.contentType] == "text/event-stream")
            #expect(response.headers[.init("X-Execution-ID")!] != nil)
            let text = String(buffer: response.body)
            #expect(!text.contains("event: output\n"))
            #expect(!text.contains("partial"))
            #expect(text.contains("event: status\n"))
            #expect(text.components(separatedBy: "event: result\n").count == 2)
            #expect(text.contains("event: result\n"))
            #expect(text.contains("event: completed\n"))
            #expect(text.contains("\"started_at\":"))
            #expect(text.contains("\"elapsed_seconds\":"))
        }
        try await client.execute(uri: "/status", method: .get) { response in
            let value = try JSONValue.parse(String(buffer: response.body))
            #expect(value["status"] == .string("healthy"))
            #expect(value["server"]?["version"] == .string("1.1.0"))
            #expect(value["executions"]?.array?.first?["status"] == .string("completed"))
            let record = try #require(value["executions"]?.array?.first)
            let startedAt = try #require(record["started_at"]?.string)
            #expect(ISO8601DateFormatter().date(from: startedAt) != nil)
            #expect(record["running_at"]?.string != nil)
            #expect(record["ended_at"]?.string != nil)
            #expect(record["elapsed_seconds"] != nil)
            #expect(record["agent_id"] == nil && record["provider"] == nil && record["error"] == nil)
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
            #expect(html.contains("Execution start time and duration"))
            #expect(html.contains("Show status updates"))
            #expect(html.contains("/assets/copy.js"))
        }
        try await client.execute(uri: "/openapi.json", method: .get) { response in
            #expect(response.status == .ok)
            let document = try JSONValue.parse(String(buffer: response.body))
            #expect(document["openapi"] == .string("3.1.0"))
            #expect(document["info"]?["version"] == .string("1.1.0"))
            let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            let readme = try String(contentsOf: packageRoot.appendingPathComponent("README.md"), encoding: .utf8)
            let reportedVersion = try #require(document["info"]?["version"]?.string)
            #expect(readme.contains("Server release: **\(reportedVersion)**"))
            #expect(document["paths"]?["/execute"]?["post"]?["operationId"] == .string("executeAgent"))
            #expect(document["paths"]?["/executions/{execution_id}/cancel"] != nil)
            #expect(document["x-agents"]?.array?.first?["id"] == .string("Echo"))
            #expect(document["x-agents"]?.array?.first?["definitions"]?.array?.first?["output_schema"] != nil)
            #expect(document["x-providers"]?.array?.first?["id"] == .string("mock"))
            let listing = try #require(document["components"]?["schemas"]?["AgentsResponse"])
            #expect(Set(listing["properties"]!.object!.keys) == Set(["agents"]))
            #expect(listing["additionalProperties"] == .bool(false))
            let item = try #require(listing["properties"]?["agents"]?["items"])
            #expect(Set(item["properties"]!.object!.keys) == Set(["id", "name", "versions"]))
            #expect(item["additionalProperties"] == .bool(false))
            let execute = try #require(document["paths"]?["/execute"]?["post"])
            #expect(execute["parameters"]?.array?.first?["name"] == .string("status"))
            #expect(execute["parameters"]?.array?.first?["schema"]?["default"] == .bool(false))
            #expect(execute["responses"]?["200"]?["content"]?["application/json"] != nil)
            #expect(execute["responses"]?["200"]?["content"]?["text/event-stream"] != nil)
            #expect(!document["x-stream-events"]!.array!.contains { $0["name"] == .string("output") })
            #expect(document["components"]?["schemas"]?["ExecutionRecord"]?["properties"]?["elapsed_seconds"]?["minimum"] == .number(0))
        }
        try await client.execute(uri: "/try?operation=getStatus", method: .get) { response in
            #expect(response.status == .ok)
            #expect(String(buffer: response.body).contains("Send request"))
            #expect(String(buffer: response.body).contains("include-status"))
        }
        try await client.execute(uri: "/assets/copy.js", method: .get) { response in
            #expect(response.status == .ok)
            #expect(response.headers[.contentType] == "text/javascript; charset=utf-8")
            #expect(String(buffer: response.body).contains("installCopyButtons"))
        }
        try await client.execute(uri: "/unknown", method: .get) { response in
            #expect(response.status == .notFound)
            let value = try JSONValue.parse(String(buffer: response.body))
            #expect(value["error"]?["code"] == .string("unknown_endpoint"))
        }
    }
}

@Test func agentsListingIsEmptyWhenNoPackagesAreRegistered() async throws {
    let registry = AgentRegistry(packages: [])
    let providers = ProviderCatalog(providers: [])
    let manager = ExecutionManager(
        registry: registry, providers: providers, runtimeRoot: FileManager.default.temporaryDirectory)
    let app = Application(
        router: ServerRoutes.makeRouter(registry: registry, providers: providers, manager: manager))
    try await app.test(.router) { client in
        try await client.execute(uri: "/agents", method: .get) { response in
            #expect(response.status == .ok)
            let value = try JSONValue.parse(String(buffer: response.body))
            #expect(value == .object(["agents": .array([])]))
        }
    }
}

private enum ResponsePackage: AgentPackageContract {
    static let id = "ResponseAgent"
    static let versions = ["1.0.0"]
    static func directory(version: String) throws -> URL { FileManager.default.temporaryDirectory }
    static func role(version: String) throws -> String { "Return a test result." }
    static func instructions(version: String) throws -> String { "Return JSON matching the schema." }
    static func outputSchema(version: String) throws -> String {
        #"{"type":"object","required":["result"],"properties":{"result":{"type":"string"}},"additionalProperties":false}"#
    }
    static func inputSchema(version: String) throws -> String? { nil }
}

private func responseManager(registry: AgentRegistry, providers: ProviderCatalog, root: URL) -> ExecutionManager {
    ExecutionManager(registry: registry, providers: providers, runtimeRoot: root, resourceSample: {
        SystemResources(
            physical_memory_bytes: 8_589_934_592, available_memory_bytes: 4_294_967_296,
            load_average: 0, cpu_count: 8)
    })
}

@Test(arguments: ["/execute", "/execute?status=false"])
func executionReturnsOnlyFinalJSONByDefault(uri: String) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let registry = AgentRegistry(packages: [ResponsePackage.self])
    let providers = ProviderCatalog(providers: [RouteProvider()])
    let manager = responseManager(registry: registry, providers: providers, root: root)
    let app = Application(router: ServerRoutes.makeRouter(registry: registry, providers: providers, manager: manager))
    try await app.test(.router) { client in
        try await client.execute(
            uri: uri, method: .post,
            headers: [.contentType: "application/json", .accept: "text/event-stream"],
            body: .init(string: #"{"agent_id":"ResponseAgent","provider":"mock","input":{"text":"final"}}"#)
        ) { response in
            #expect(response.status == .ok)
            #expect(response.headers[.contentType] == "application/json")
            #expect(response.headers[.init("X-Execution-ID")!] != nil)
            let value = try JSONValue.parse(String(buffer: response.body))
            #expect(value == .object(["result": .string("final")]))
        }
    }
}

@Test(arguments: [RouteProvider.Outcome.schemaFailure, .providerFailure, .cancelled], [false, true])
private func executionErrorsMatchTheSelectedResponseMode(outcome: RouteProvider.Outcome, includeStatus: Bool) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let registry = AgentRegistry(packages: [ResponsePackage.self])
    let providers = ProviderCatalog(providers: [RouteProvider(outcome: outcome)])
    let manager = responseManager(registry: registry, providers: providers, root: root)
    let app = Application(router: ServerRoutes.makeRouter(registry: registry, providers: providers, manager: manager))
    try await app.test(.router) { client in
        try await client.execute(
            uri: includeStatus ? "/execute?status=true" : "/execute", method: .post, headers: [.contentType: "application/json"],
            body: .init(string: #"{"agent_id":"ResponseAgent","provider":"mock","input":{}}"#)
        ) { response in
            if includeStatus {
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "text/event-stream")
                let text = String(buffer: response.body)
                #expect(!text.contains("event: result\n") && !text.contains("event: completed\n"))
                #expect(!text.contains("event: output\n") && !text.contains("partial"))
                #expect(text.contains(outcome == .cancelled ? "event: cancelled\n" : "event: failed\n"))
                if outcome != .cancelled {
                    #expect(text.contains(outcome == .schemaFailure ? "output_schema_validation_failed" : "provider_execution_failed"))
                }
                return
            }
            #expect(response.status == .internalServerError)
            #expect(response.headers[.contentType] == "application/json")
            let value = try JSONValue.parse(String(buffer: response.body))
            let expected = switch outcome {
            case .schemaFailure: "output_schema_validation_failed"
            case .providerFailure: "provider_execution_failed"
            case .cancelled: "execution_cancelled"
            case .success: "unexpected"
            }
            #expect(value["error"]?["code"] == .string(expected))
            #expect(value["error"]?["execution_id"]?.string == response.headers[.init("X-Execution-ID")!])
            #expect(value["result"] == nil)
        }
    }
}

@Test(arguments: ["/execute?status=invalid", "/execute?status=", "/execute?status=true&status=false"])
func invalidStatusQueryIsRejectedBeforeExecution(uri: String) async throws {
    let registry = AgentRegistry(packages: [ResponsePackage.self])
    let provider = RouteProvider()
    let providers = ProviderCatalog(providers: [provider])
    let manager = ExecutionManager(registry: registry, providers: providers, runtimeRoot: FileManager.default.temporaryDirectory)
    let app = Application(router: ServerRoutes.makeRouter(registry: registry, providers: providers, manager: manager))
    try await app.test(.router) { client in
        try await client.execute(
            uri: uri, method: .post, headers: [.contentType: "application/json"],
            body: .init(string: #"{"agent_id":"ResponseAgent","provider":"mock","input":{}}"#)
        ) { response in
            #expect(response.status == .badRequest)
            let value = try JSONValue.parse(String(buffer: response.body))
            #expect(value["error"]?["code"] == .string("invalid_request"))
            #expect(await provider.readiness.count == 0)
        }
    }
    #expect(await manager.snapshot().records.isEmpty)
}
