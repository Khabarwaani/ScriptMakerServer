import Foundation

/// Bootstrap configuration. Remote binding is intentionally unavailable until
/// authentication is implemented.
public struct ServerConfiguration: Sendable {
    public let host = "127.0.0.1"
    public let port: Int
    public let agentsDirectory: URL

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        let portValue = environment["AGENT_SERVER_PORT"] ?? "8080"
        guard let port = Int(portValue), (1...65535).contains(port) else {
            throw ConfigurationError.invalidPort
        }
        self.port = port
        self.agentsDirectory = URL(
            fileURLWithPath: environment["AGENT_SERVER_AGENTS_DIR"] ?? "Agents",
            isDirectory: true
        ).standardizedFileURL
    }

    public enum ConfigurationError: Error {
        case invalidPort
    }
}
