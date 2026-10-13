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
        do { try await run() } catch {
            if let configurationError = error as? ServerConfiguration.ConfigurationError {
                print("AgentServer: \(configurationError)")
            } else if let instanceError = error as? ServerInstance.InstanceError {
                print("AgentServer: \(instanceError)")
            } else if let portError = error as? TestingPortAllocator.AllocationError {
                print("AgentServer: \(portError)")
            } else if let failure = error as? AgentError {
                print("AgentServer: \(failure.code): \(failure.message)")
            } else {
                print(
                    "AgentServer could not start or complete shutdown. Check port availability and filesystem permissions."
                )
            }
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
        if environment["AGENT_SERVER_CONFIG"] == nil {
            environment["AGENT_SERVER_CONFIG"] = root.appendingPathComponent("config/server.json").path
        }
        let configuration = try ServerConfiguration(environment: environment, workingDirectory: root)
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["stop"] {
            guard configuration.serverEnvironment != .testing, let port = configuration.port else {
                throw AgentError("unsafe_test_stop", "Stop a test server using the PID owned by its test run, not a port-wide stop command.")
            }
            let stopped = try await ServerInstance.stop(
                port: port, timeoutSeconds: configuration.shutdownTimeoutSeconds)
            print(
                stopped
                    ? "AgentServer stopped gracefully."
                    : "No managed AgentServer is running on port \(port).")
            return
        }
        guard arguments.isEmpty else {
            print("Usage: AgentServer [stop]")
            exit(2)
        }
        if configuration.serverEnvironment == .testing {
            try await TestingPortAllocator.withAvailablePort(
                configuration: configuration.testingPorts, host: configuration.host,
                preferredPort: configuration.port
            ) { port in
                try await runServer(configuration: configuration, port: port)
            }
        } else if let port = configuration.port {
            try await runServer(configuration: configuration, port: port)
        }
    }

    private static func runServer(configuration: ServerConfiguration, port: Int) async throws {
        let testing = configuration.serverEnvironment == .testing
        let instance: ServerInstance
        do {
            instance = try await ServerInstance.start(
                port: port, timeoutSeconds: configuration.shutdownTimeoutSeconds, replaceExisting: !testing)
        } catch ServerInstance.InstanceError.concurrentStartup where testing {
            throw TestingPortAllocator.AllocationError.portInUse
        }
        defer { withExtendedLifetime(instance) {} }
        GeneratedAgentDocumentationCatalog.documentation = GeneratedAgentDocumentationRegistry.documentation
        let registry = AgentRegistry(
            validationMetadata: GeneratedAgentValidationCatalog.metadata,
            root: configuration.agentsDirectory
        )
        #if os(macOS) || os(Linux)
        let ownership = try WorkerOwnershipStore(url: WorkerOwnershipStore.fileURL(port: port))
        let cleanup = try await ownership.cleanupAfterRestart()
        print("AgentServer worker restart cleanup: \(cleanup.terminated) terminated, \(cleanup.preserved) preserved.")
        #else
        let ownership: WorkerOwnershipStore? = nil
        #endif
        let adapters: [any AIProvider] = configuration.providers.compactMap { id, settings in
            guard let kind = CLIProvider.Kind(rawValue: id) else { return nil }
            return CLIProvider(kind: kind, settings: settings, ownership: ownership)
        }
        let providers = ProviderCatalog(providers: adapters)
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentServer", isDirectory: true)
            .appendingPathComponent("executions-\(port).jsonl")
        let sessionLog = try ExecutionSessionLog(url: logURL)
        let manager = ExecutionManager(
            registry: registry, providers: providers, runtimeRoot: configuration.runtimeDirectory,
            maxProcesses: configuration.maxProcesses, maxQueued: configuration.maxQueuedExecutions,
            timeoutSeconds: configuration.executionTimeoutSeconds,
            retentionSeconds: configuration.retentionSeconds, sessionLog: sessionLog,
            providerPoolSize: configuration.providerPoolSize, ownership: ownership)
        let router = ServerRoutes.makeRouter(registry: registry, providers: providers, manager: manager)
        let readiness = StartupReadiness()
        let app = Application(
            router: router,
            configuration: .init(address: .hostname(configuration.host, port: port)),
            onServerRunning: { _ in
                await readiness.markStarted()
                let message = "AgentServer: http://\(configuration.host):\(port)/ — API help: /help\nAgentServer execution log: \(logURL.path)\n"
                try? FileHandle.standardOutput.write(contentsOf: Data(message.utf8))
            })
        var groupConfiguration = ServiceGroupConfiguration(
            services: [
                app,
                ExecutionService(
                    manager: manager, shutdownTimeoutSeconds: configuration.shutdownTimeoutSeconds),
            ],
            gracefulShutdownSignals: [.sigterm, .sigint], logger: app.logger
        )
        groupConfiguration.maximumGracefulShutdownDuration = .seconds(configuration.shutdownTimeoutSeconds)
        groupConfiguration.maximumCancellationDuration = .seconds(15)
        let group = ServiceGroup(configuration: groupConfiguration)
        do {
            try await group.run()
        } catch {
            if testing, await !readiness.started, TestingPortAllocator.isAddressInUse(error) {
                throw TestingPortAllocator.AllocationError.portInUse
            }
            throw error
        }
        print("AgentServer shutdown complete.")
    }
}

private actor StartupReadiness {
    var started = false
    func markStarted() { started = true }
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
        do { try await gracefulShutdown() } catch {}
        await manager.shutdown(timeoutSeconds: shutdownTimeoutSeconds)
    }
}
