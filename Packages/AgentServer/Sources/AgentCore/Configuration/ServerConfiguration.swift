import Foundation

/// Bootstrap configuration. Remote binding is intentionally unavailable until
/// authentication is implemented.
public struct ServerConfiguration: Sendable {
    public let host: String
    public let serverEnvironment: ServerEnvironment
    /// Nil in automatic testing mode; the allocator supplies the bound port.
    public let port: Int?
    public let testingPorts: TestingPortConfiguration
    public let agentsDirectory: URL
    public let shutdownTimeoutSeconds: Int
    public let executionTimeoutSeconds: Int
    public let maxProcesses: Int
    public let providerPoolSize: Int
    public let maxQueuedExecutions: Int
    public let retentionSeconds: Int
    public let runtimeDirectory: URL
    public let providers: [String: ProviderSettings]

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws {
        let configPath = environment["AGENT_SERVER_CONFIG"] ?? "config/server.json"
        let baseDirectory = URL(fileURLWithPath: workingDirectory.path, isDirectory: true)
        let configURL = URL(fileURLWithPath: configPath, relativeTo: baseDirectory).standardizedFileURL
        let settings: Settings
        if FileManager.default.fileExists(atPath: configURL.path) {
            do {
                settings = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: configURL))
            } catch {
                throw ConfigurationError.invalidConfigurationFile
            }
        } else if environment["AGENT_SERVER_CONFIG"] != nil {
            throw ConfigurationError.configurationFileNotFound
        } else {
            settings = Settings()
        }
        let host = settings.host ?? "127.0.0.1"
        guard host == "127.0.0.1" else { throw ConfigurationError.remoteBindingUnavailable }
        self.host = host
        guard let selectedEnvironment = ServerEnvironment(
            rawValue: environment["AGENT_SERVER_ENV"] ?? settings.environment ?? "development") else {
            throw ConfigurationError.invalidEnvironment
        }
        self.serverEnvironment = selectedEnvironment
        let productionPort = settings.ports?.production ?? 8081
        // Preserve old custom config files while migrating packaged defaults.
        let developmentPort = settings.ports?.development ?? settings.port ?? 8080
        let testingPorts = try settings.ports?.testing ?? TestingPortConfiguration()
        guard (1...65535).contains(productionPort), (1...65535).contains(developmentPort),
            productionPort != developmentPort,
            !testingPorts.range.contains(productionPort), !testingPorts.range.contains(developmentPort) else {
            throw ConfigurationError.invalidPortConfiguration
        }
        self.testingPorts = testingPorts
        if let portValue = environment["AGENT_SERVER_PORT"] {
            guard let port = Int(portValue), (1...65535).contains(port) else {
                throw ConfigurationError.invalidPort
            }
            let isolated = switch selectedEnvironment {
            case .testing: testingPorts.range.contains(port)
            case .production: port != developmentPort && !testingPorts.range.contains(port)
            case .development: port != productionPort && !testingPorts.range.contains(port)
            }
            guard isolated else { throw ConfigurationError.invalidPortConfiguration }
            self.port = port
        } else {
            self.port = switch selectedEnvironment {
            case .production: productionPort
            case .development: developmentPort
            case .testing: nil
            }
        }
        self.agentsDirectory =
            URL(
                fileURLWithPath: environment["AGENT_SERVER_AGENTS_DIR"] ?? settings.agents_directory
                    ?? "Agents",
                isDirectory: true,
                relativeTo: baseDirectory
            ).standardizedFileURL
        let timeout = settings.shutdown_timeout_seconds ?? 900
        guard (1...900).contains(timeout) else { throw ConfigurationError.invalidShutdownTimeout }
        self.shutdownTimeoutSeconds = timeout
        let executionTimeout = settings.execution_timeout_seconds ?? 1800
        let processes = settings.max_processes ?? 8
        let poolSize = settings.provider_pool_size ?? min(5, processes)
        let queued = settings.max_queued_executions ?? 64
        let retention = settings.retention_seconds ?? 3600
        guard (1...86400).contains(executionTimeout), (1...128).contains(processes),
            (1...10000).contains(queued), (1...86400).contains(retention), (0...processes).contains(poolSize)
        else {
            throw ConfigurationError.invalidConfigurationFile
        }
        self.executionTimeoutSeconds = executionTimeout
        self.maxProcesses = processes
        self.providerPoolSize = poolSize
        self.maxQueuedExecutions = queued
        self.retentionSeconds = retention
        if let path = settings.runtime_directory {
            self.runtimeDirectory =
                URL(fileURLWithPath: path, isDirectory: true, relativeTo: baseDirectory).standardizedFileURL
        } else {
            self.runtimeDirectory = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Khabarwaani/AgentServer/Executions", isDirectory: true)
        }
        self.providers =
            settings.providers ?? [
                "codex": ProviderSettings(executable: "codex"),
                "antigravity": ProviderSettings(executable: "agy"),
                "grok": ProviderSettings(executable: "grok"),
            ]
        guard providers.keys.allSatisfy({ CLIProvider.Kind(rawValue: $0) != nil }),
            providers.values.allSatisfy({ $0.reasoning_effort == nil || ["none", "minimal", "low", "medium", "high", "xhigh", "max"].contains($0.reasoning_effort!) }) else {
            throw ConfigurationError.invalidConfigurationFile
        }
    }

    private struct Settings: Decodable {
        var host: String?
        var environment: String?
        var ports: PortConfiguration?
        var port: Int?
        var agents_directory: String?
        var shutdown_timeout_seconds: Int?
        var execution_timeout_seconds: Int?
        var max_processes: Int?
        var provider_pool_size: Int?
        var max_queued_executions: Int?
        var retention_seconds: Int?
        var runtime_directory: String?
        var providers: [String: ProviderSettings]?
    }

    public enum ConfigurationError: Error, CustomStringConvertible {
        case invalidPort
        case invalidEnvironment
        case invalidPortConfiguration
        case invalidConfigurationFile
        case configurationFileNotFound
        case remoteBindingUnavailable
        case invalidShutdownTimeout

        public var description: String {
            switch self {
            case .invalidPort: "Server port must be between 1 and 65535."
            case .invalidEnvironment: "Server environment must be production, development or testing."
            case .invalidPortConfiguration:
                "Production and development ports must be distinct valid ports outside the testing range; testing requires a valid range and 1 through 30 attempts."
            case .invalidConfigurationFile: "Server configuration must contain valid settings JSON."
            case .configurationFileNotFound: "The specified server configuration file does not exist."
            case .remoteBindingUnavailable:
                "Only 127.0.0.1 is supported until remote authentication is implemented."
            case .invalidShutdownTimeout: "Shutdown timeout must be between 1 and 900 seconds."
            }
        }
    }
}
