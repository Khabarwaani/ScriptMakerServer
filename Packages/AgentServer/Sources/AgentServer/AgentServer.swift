import AgentCore
import Foundation
import Hummingbird
import ServiceLifecycle
#if SWIFT_PACKAGE
import AgentResources
#endif

@main
struct AgentServer {
    static func main() async {
        do { try await run() }
        catch {
            if let configurationError = error as? ServerConfiguration.ConfigurationError { print("AgentServer: \(configurationError)") }
            else if let instanceError = error as? ServerInstance.InstanceError { print("AgentServer: \(instanceError)") }
            else { print("AgentServer could not start or complete shutdown. Check port availability and filesystem permissions.") }
            exit(1)
        }
    }

    private static func run() async throws {
        #if SWIFT_PACKAGE
        let root = AgentResources.root
        #else
        let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        #endif
        var environment = ProcessInfo.processInfo.environment
        if environment["AGENT_SERVER_CONFIG"] == nil { environment["AGENT_SERVER_CONFIG"] = root.appendingPathComponent("config/server.json").path }
        let configuration = try ServerConfiguration(environment: environment, workingDirectory: root)
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["stop"] {
            let stopped = try await ServerInstance.stop(port: configuration.port, timeoutSeconds: configuration.shutdownTimeoutSeconds)
            print(stopped ? "AgentServer stopped gracefully." : "No managed AgentServer is running on port \(configuration.port).")
            return
        }
        guard arguments.isEmpty else { print("Usage: AgentServer [stop]"); exit(2) }
        let instance = try await ServerInstance.start(port: configuration.port, timeoutSeconds: configuration.shutdownTimeoutSeconds)
        defer { withExtendedLifetime(instance) {} }
        let registry = AgentRegistry(root: configuration.agentsDirectory)
        let adapters: [any AIProvider] = configuration.providers.compactMap { id, settings in
            guard settings.enabled, let kind = CLIProvider.Kind(rawValue: id) else { return nil }
            return CLIProvider(kind: kind, settings: settings)
        }
        let providers = ProviderCatalog(providers: adapters)
        let manager = ExecutionManager(registry: registry, providers: providers, runtimeRoot: configuration.runtimeDirectory,
                                       maxProcesses: configuration.maxProcesses, maxQueued: configuration.maxQueuedExecutions,
                                       timeoutSeconds: configuration.executionTimeoutSeconds, retentionSeconds: configuration.retentionSeconds)
        let router = ServerRoutes.makeRouter(registry: registry, providers: providers, manager: manager)
        let app = Application(router: router, configuration: .init(address: .hostname(configuration.host, port: configuration.port)))
        var groupConfiguration = ServiceGroupConfiguration(
            services: [app, ExecutionService(manager: manager, shutdownTimeoutSeconds: configuration.shutdownTimeoutSeconds)],
            gracefulShutdownSignals: [.sigterm, .sigint], logger: app.logger
        )
        groupConfiguration.maximumGracefulShutdownDuration = .seconds(configuration.shutdownTimeoutSeconds)
        groupConfiguration.maximumCancellationDuration = .seconds(15)
        let group = ServiceGroup(configuration: groupConfiguration)
        print("AgentServer: http://\(configuration.host):\(configuration.port)/ — API help: /help")
        try await group.run()
        print("AgentServer shutdown complete.")
    }
}

private struct ExecutionService: Service {
    let manager: ExecutionManager
    let shutdownTimeoutSeconds: Int
    func run() async throws {
        let maintenance = Task {
            while !Task.isCancelled {
                await manager.maintenance()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
        defer { maintenance.cancel() }
        do { try await gracefulShutdown() } catch { }
        await manager.shutdown(timeoutSeconds: shutdownTimeoutSeconds)
    }
}
