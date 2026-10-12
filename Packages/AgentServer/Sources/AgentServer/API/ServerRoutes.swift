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
                server: .init(version: "1.0.0", uptime_seconds: Int(Date().timeIntervalSince(startedAt))),
                active_executions: snapshot.activeCount, queued_executions: snapshot.queuedCount,
                system_resources: SystemResources.sample(),
                provider_resident_memory_bytes: snapshot.residentMemoryBytes,
                executions: snapshot.records, providers: providers.statuses()))
        }
        router.post(RouterPath(APIOperation.executeAgent.path)) { request, context in
            do {
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
                let execution = try await manager.execute(input)
                return Response(
                    status: .ok,
                    headers: [
                        .contentType: "text/event-stream", .cacheControl: "no-cache",
                        .init("X-Execution-ID")!: execution.id,
                    ],
                    body: .init { writer in
                        do {
                            for await event in execution.events {
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
        let executions: [ExecutionRecord]
        let providers: [ProviderStatus]
        struct ServerInfo: Codable {
            let version: String
            let uptime_seconds: Int
        }
    }

    private static func webPage(_ name: String) throws -> Response {
        #if SWIFT_PACKAGE
            let url = AgentResources.root.appendingPathComponent("Web/\(name).html")
        #else
            let url = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
                .appendingPathComponent("Web/\(name).html")
        #endif
        let html = try String(contentsOf: url, encoding: .utf8)
        return Response(
            status: .ok, headers: [.contentType: "text/html; charset=utf-8"],
            body: .init(byteBuffer: .init(string: html)))
    }

    static func jsonResponse<T: Encodable>(_ value: T, status: HTTPResponse.Status = .ok) throws -> Response {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return Response(
            status: status, headers: [.contentType: "application/json"],
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
