import Foundation
import AgentAtom

/// A protocol representing an `AgenticSessionProtocol` that is driven by a terminal CLI subprocess.
///
/// Any terminal session package or custom provider conforming to `TerminalSessionProtocol` can be
/// plugged directly into `TerminalAgentSession` or registered dynamically.
public protocol TerminalSessionProtocol: AgenticSessionProtocol {
    /// The configuration describing the binary path, arguments, working directory, and metadata.
    var configuration: TerminalAgentConfiguration { get }

    /// Clears any in-memory conversation context accumulated by this session.
    func clearMemory()
}

extension TerminalSessionProtocol {
    public func clearMemory() {}
}

/// A provider descriptor that can instantiate a `TerminalSessionProtocol` given a configuration.
public struct TerminalProvider: Sendable {
    public let name: String
    public let defaultExecutablePath: String
    private let factory: @Sendable (TerminalAgentConfiguration) -> (any TerminalSessionProtocol)?

    public init(
        name: String,
        defaultExecutablePath: String,
        factory: @escaping @Sendable (TerminalAgentConfiguration) -> (any TerminalSessionProtocol)?
    ) {
        self.name = name
        self.defaultExecutablePath = defaultExecutablePath
        self.factory = factory
    }

    /// Convenience initializer to create a provider for ANY command-line agent tool (e.g. `muse`, `claude`, `ollama`).
    public static func generic(
        name: String,
        executablePath: String,
        argumentBuilder: (@Sendable (String, String, JSONString, TerminalAgentConfiguration) -> [String])? = nil
    ) -> TerminalProvider {
        TerminalProvider(name: name, defaultExecutablePath: executablePath) { config in
            GenericTerminalSession(configuration: config, argumentBuilder: argumentBuilder)
        }
    }

    /// Attempts to build a session instance using this provider with the given configuration.
    public func createSession(configuration: TerminalAgentConfiguration) -> (any TerminalSessionProtocol)? {
        factory(configuration)
    }
}
