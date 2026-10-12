import AgentCore
import Foundation
import Hummingbird

@main
struct AgentServer {
    static func main() async throws {
        let configuration = try ServerConfiguration()
        let startedAt = Date()
        let router = Router()

        router.get("/") { _, _ in try webPage("index") }
        router.get("/help") { _, _ in try webPage("help") }
        router.post("/execute") { _, _ in
            Response(status: .notImplemented, headers: [.contentType: "application/json"], body: .init(byteBuffer: .init(string: "{\"error\":{\"code\":\"execution_not_implemented\",\"message\":\"This package is a bootstrap. Provider execution is not implemented yet.\"}}")))
        }

        router.get("/status") { _, _ -> StatusResponse in
            StatusResponse(
                status: "healthy",
                implementation_stage: "bootstrap",
                server: .init(version: "0.1.0", uptime_seconds: Int(Date().timeIntervalSince(startedAt))),
                active_executions: 0,
                executions: []
            )
        }

        let app = Application(
            router: router,
            configuration: .init(address: .hostname(configuration.host, port: configuration.port))
        )
        try await app.runService()
    }
}

private func webPage(_ name: String) throws -> Response {
    #if SWIFT_PACKAGE
    guard let url = Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Web") else {
        throw HTTPError(.internalServerError)
    }
    #else
    let url = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        .appendingPathComponent("Web/\(name).html")
    #endif
    let html = try String(contentsOf: url, encoding: .utf8)
    return Response(status: .ok, headers: [.contentType: "text/html; charset=utf-8"], body: .init(byteBuffer: .init(string: html)))
}

private struct StatusResponse: ResponseEncodable {
    let status: String
    let implementation_stage: String
    let server: ServerInfo
    let active_executions: Int
    let executions: [String]

    struct ServerInfo: Codable {
        let version: String
        let uptime_seconds: Int
    }
}
