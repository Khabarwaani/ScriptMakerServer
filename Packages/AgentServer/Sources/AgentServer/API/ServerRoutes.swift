import AgentCore
import Foundation
import Hummingbird

#if SWIFT_PACKAGE
    import AgentResources
#endif

struct ServerRoutes {
    static func makeRouter(registry: AgentRegistry, providers: ProviderCatalog, manager: ExecutionManager)
        -> Router<BasicRequestContext>
    {
        let startedAt = Date()
        let router = Router()
        router.get("/") { _, _ in try webPage("index") }
        router.get("/help") { _, _ in try webPage("help") }
        router.get("/try") { _, _ in try webPage("try") }
        router.get("/logs") { _, _ in try webPage("logs") }
        router.get("/agent") { _, _ in try webPage("agent") }
        router.get("/agent/try") { _, _ in try webPage("agent-try") }
        router.get("/agent/format") { _, _ in try webPage("agent-format") }
        router.get(RouterPath("/agents/{agent_id}")) { _, _ in try webPage("agent") }
        router.get(RouterPath("/agents/{agent_id}/try")) { _, _ in try webPage("agent-try") }
        router.get(RouterPath("/agents/{agent_id}/format")) { _, _ in try webPage("agent-format") }
        router.get(RouterPath("/agents/{agent_id}/schema")) { _, _ in try webPage("agent-format") }
        router.get(RouterPath("/help/agents/{agent_id}")) { _, _ in try webPage("agent") }
        router.get(RouterPath("/help/agents/{agent_id}/format")) { _, _ in try webPage("agent-format") }
        router.get(RouterPath("/try/agents/{agent_id}")) { _, _ in try webPage("agent-try") }
        router.get(RouterPath(APIOperation.getExecutionLogs.path)) { _, _ in
            do { return try jsonResponse(["entries": await manager.recentExecutionLogs()]) }
            catch { return errorResponse(error) }
        }
        router.get(RouterPath(APIOperation.downloadExecutionLog.path)) { _, _ in
            do {
                let snapshot = try await manager.executionLogFile()
                // Stream a fixed snapshot in chunks, even when the session log is large.
                let handle = try FileHandle(forReadingFrom: snapshot.url)
                return Response(status: .ok, headers: [
                    .contentType: "application/x-ndjson",
                    .cacheControl: "no-store",
                    .init("Content-Disposition")!: "attachment; filename=executions.jsonl",
                ], body: .init { writer in
                    defer { try? handle.close() }
                    var remaining = snapshot.length
                    while remaining > 0 {
                        let chunk = try handle.read(upToCount: Int(min(remaining, 8192))) ?? Data()
                        guard !chunk.isEmpty else { break }
                        remaining -= UInt64(chunk.count)
                        try await writer.write(.init(bytes: chunk))
                    }
                    try await writer.finish(nil)
                })
            } catch { return errorResponse(error) }
        }
        router.get("/assets/schema-form.js") { _, _ in
            try webAsset("schema-form.js", contentType: "text/javascript; charset=utf-8")
        }
        router.get("/assets/errors.js") { _, _ in
            try webAsset("errors.js", contentType: "text/javascript; charset=utf-8")
        }
        router.get("/assets/copy.js") { _, _ in
            try webAsset("copy.js", contentType: "text/javascript; charset=utf-8")
        }
        router.get(RouterPath(APIOperation.getSpecification.path)) { _, _ in
            do {
                let agents = await registry.list()
                let configuredProviders = await providers.statuses()
                return try jsonResponse(
                    APISpecification.document(agents: agents, providers: configuredProviders))
            } catch { return errorResponse(error) }
        }
        router.get(RouterPath(APIOperation.listAgents.path)) { _, _ -> AgentsResponse in
            await AgentsResponse(agents: registry.availableAgents())
        }
        router.get(RouterPath(APIOperation.getStatus.path)) { _, _ in
            let snapshot = await manager.snapshot()
            return try await jsonResponse(StatusResponse(
                status: snapshot.accepting ? "healthy" : "shutting_down",
                server: .init(version: "2.0.0", uptime_seconds: Int(Date().timeIntervalSince(startedAt))),
                active_executions: snapshot.activeCount, queued_executions: snapshot.queuedCount,
                system_resources: SystemResources.sample(),
                provider_resident_memory_bytes: snapshot.residentMemoryBytes,
                worker_pool: snapshot.worker_pool,
                executions: snapshot.records, providers: providers.statuses()))
        }
        router.post(RouterPath(APIOperation.executeAgent.path)) { request, context in
            do {
                let statusValues = request.uri.queryParameters[values: "status"]
                guard statusValues.count <= 1,
                    statusValues.allSatisfy({ $0 == "true" || $0 == "false" })
                else {
                    throw AgentError("invalid_request", "The status query parameter must be true or false and appear at most once.")
                }
                let includeStatus = statusValues.first == "true"
                let input: ExecuteRequest
                do {
                    let body = try await request.body.collect(upTo: 1_048_576)
                    input = try JSONDecoder().decode(ExecuteRequest.self, from: Data(body.readableBytesView))
                } catch DecodingError.keyNotFound {
                    throw AgentError(
                        "invalid_request", "The request must include agent_id, provider and input.")
                } catch {
                    throw AgentError(
                        "invalid_json",
                        "The request must be valid JSON matching the execution request schema.")
                }
                let execution = try await manager.execute(input, streaming: includeStatus)
                if !includeStatus {
                    var response: Response
                    do {
                        let final = try await finalResult(execution)
                        let status: HTTPResponse.Status = final["error"] != nil ? .init(code: 422) : .ok
                        response = try jsonResponse(final, status: status)
                    } catch {
                        var failure = error as? AgentError
                            ?? AgentError("internal_error", "Execution could not complete.")
                        failure.execution_id = execution.id
                        response = errorResponse(failure)
                    }
                    await manager.detach(execution.id)
                    response.headers[.init("X-Execution-ID")!] = execution.id
                    return response
                }
                return Response(
                    status: .ok,
                    headers: [
                        .contentType: "text/event-stream", .cacheControl: "no-cache",
                        .init("X-Execution-ID")!: execution.id,
                    ],
                    body: .init { writer in
                        do {
                            for await event in execution.events {
                                // Opt-in status streams expose progress and the validated result,
                                // never provisional provider text or transport annotations.
                                if event.name == "output" { continue }
                                try await writer.write(.init(string: try event.sse()))
                            }
                            await manager.detach(execution.id)
                            try await writer.finish(nil)
                        } catch {
                            await manager.detach(execution.id)
                            throw error
                        }
                    })
            } catch { return errorResponse(error) }
        }
        router.post(RouterPath(APIOperation.cancelExecution.path)) { _, context in
            do {
                let id = try context.parameters.require("execution_id")
                let record = try await manager.cancel(id)
                return try jsonResponse(CancelResponse(execution_id: id, status: record.status))
            } catch { return errorResponse(error) }
        }
        router.add(middleware: NotFoundMiddleware())
        return router
    }

    private static func finalResult(_ execution: AcceptedExecution) async throws -> JSONValue {
        var result: JSONValue?
        for await event in execution.events {
            try Task.checkCancellation()
            switch event.name {
            case "result": result = event.data["result"]
            case "completed":
                guard let result else { break }
                return result
            case "failed":
                if let error = event.data["error"] {
                    throw try JSONDecoder().decode(AgentError.self, from: error.data())
                }
                throw AgentError("internal_error", "Execution could not complete.", executionID: execution.id)
            case "cancelled":
                throw AgentError("execution_cancelled", "The execution was cancelled.", executionID: execution.id)
            default: break
            }
        }
        throw AgentError(
            "execution_stream_closed", "Execution ended without a validated final result.",
            executionID: execution.id)
    }

    private struct AgentsResponse: ResponseEncodable {
        let agents: [AgentListItem]
    }
    private struct CancelResponse: Encodable {
        let execution_id: String
        let status: String
    }
    private struct StatusResponse: ResponseEncodable {
        let status: String
        let server: ServerInfo
        let active_executions: Int
        let queued_executions: Int
        let system_resources: SystemResources
        let provider_resident_memory_bytes: UInt64
        let worker_pool: WorkerPoolSnapshot?
        let executions: [ExecutionRecord]
        let providers: [ProviderStatus]
        struct ServerInfo: Codable {
            let version: String
            let uptime_seconds: Int
        }
    }

    private static func webPage(_ name: String) throws -> Response {
        try webAsset(name + ".html", contentType: "text/html; charset=utf-8")
    }

    private static func webAsset(_ name: String, contentType: String) throws -> Response {
        #if SWIFT_PACKAGE
            let url = AgentResources.root.appendingPathComponent("Web/\(name)")
        #else
            let url = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
                .appendingPathComponent("Web/\(name)")
        #endif
        let html = try String(contentsOf: url, encoding: .utf8)
        return Response(
            status: .ok, headers: [.contentType: contentType],
            body: .init(byteBuffer: .init(string: html)))
    }

    static func jsonResponse<T: Encodable>(_ value: T, status: HTTPResponse.Status = .ok) throws -> Response {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return Response(
            status: status, headers: [.contentType: "application/json", .cacheControl: "no-store"],
            body: .init(byteBuffer: .init(bytes: data)))
    }
    static func errorResponse(_ error: any Error) -> Response {
        let failure =
            error as? AgentError ?? AgentError("internal_error", "The server could not complete the request.")
        struct Envelope: Encodable { let error: AgentError }
        return (try? jsonResponse(Envelope(error: failure), status: .init(code: failure.httpStatus)))
            ?? Response(status: .internalServerError)
    }
}

private struct NotFoundMiddleware: RouterMiddleware {
    func handle(
        _ request: Request, context: BasicRequestContext,
        next: (Request, BasicRequestContext) async throws -> Response
    ) async throws -> Response {
        do { return try await next(request, context) } catch let error as HTTPError
            where error.status == .notFound
        {
            return try ServerRoutes.jsonResponse(
                JSONValue.object([
                    "error": .object([
                        "code": .string("unknown_endpoint"),
                        "message": .string("The requested endpoint does not exist."),
                    ])
                ]), status: .notFound)
        } catch { return ServerRoutes.errorResponse(error) }
    }
}
