import Foundation
import Synchronization
import AgentAtom

/// Unified terminal agent session that automatically detects installed CLI tools or delegates to a specified provider.
public final class TerminalAgentSession: AgenticSessionProtocol, @unchecked Sendable {
    public enum Provider: String, Sendable, CaseIterable {
        case codex
        case antigravity = "agy"
        case grok
    }

    public let configuration: Configuration
    private let underlyingSession: any AgenticSessionProtocol

    public var executionMetadata: [AgenticExecutionMetadata] {
        underlyingSession.executionMetadata
    }

    /// Creates a session with automatic detection of available terminal providers in order: Codex -> Antigravity -> Grok.
    public convenience init?(workingDirectory: URL? = nil, metadata: AgenticExecutionMetadata.Fields = []) {
        if let codex = CodexTerminalSession(configuration: .init(executablePath: "codex", workingDirectory: workingDirectory, metadata: metadata)) {
            self.init(provider: .codex, session: codex, configuration: .init(provider: .codex, executablePath: "codex", workingDirectory: workingDirectory, metadata: metadata))
            return
        }
        if let agy = AntigravityTerminalSession(configuration: .init(executablePath: "agy", workingDirectory: workingDirectory, metadata: metadata)) {
            self.init(provider: .antigravity, session: agy, configuration: .init(provider: .antigravity, executablePath: "agy", workingDirectory: workingDirectory, metadata: metadata))
            return
        }
        if let grok = GrokTerminalSession(configuration: .init(executablePath: "grok", workingDirectory: workingDirectory, metadata: metadata)) {
            self.init(provider: .grok, session: grok, configuration: .init(provider: .grok, executablePath: "grok", workingDirectory: workingDirectory, metadata: metadata))
            return
        }
        return nil
    }

    /// Creates a session explicitly for a given provider with optional custom configuration.
    public init?(provider: Provider, configuration: Configuration = Configuration()) {
        self.configuration = configuration
        switch provider {
        case .codex:
            guard let session = CodexTerminalSession(configuration: .init(
                executablePath: configuration.executablePath ?? "codex",
                model: configuration.model,
                workingDirectory: configuration.workingDirectory,
                extraArguments: configuration.extraArguments,
                metadata: configuration.metadata
            )) else { return nil }
            self.underlyingSession = session

        case .antigravity:
            guard let session = AntigravityTerminalSession(configuration: .init(
                executablePath: configuration.executablePath ?? "agy",
                model: configuration.model,
                workingDirectory: configuration.workingDirectory,
                extraArguments: configuration.extraArguments,
                metadata: configuration.metadata
            )) else { return nil }
            self.underlyingSession = session

        case .grok:
            guard let session = GrokTerminalSession(configuration: .init(
                executablePath: configuration.executablePath ?? "grok",
                model: configuration.model,
                workingDirectory: configuration.workingDirectory,
                extraArguments: configuration.extraArguments,
                metadata: configuration.metadata
            )) else { return nil }
            self.underlyingSession = session
        }
    }

    private init(provider: Provider, session: any AgenticSessionProtocol, configuration: Configuration) {
        self.underlyingSession = session
        self.configuration = configuration
    }

    public func respond(
        to input: String,
        instructions: String,
        schema: JSONString,
        for operation: ObjectIdentifier
    ) async -> Result<String, AgenticError> {
        await underlyingSession.respond(to: input, instructions: instructions, schema: schema, for: operation)
    }

    public func stream(
        to input: String,
        instructions: String,
        schema: JSONString,
        for operation: ObjectIdentifier,
        yield: @Sendable (String) async -> Void
    ) async -> Result<String, AgenticError> {
        await underlyingSession.stream(to: input, instructions: instructions, schema: schema, for: operation, yield: yield)
    }

    public func pause(_ operation: ObjectIdentifier) async throws(AgenticError) {
        try await underlyingSession.pause(operation)
    }

    public func resume(_ operation: ObjectIdentifier) async throws(AgenticError) {
        try await underlyingSession.resume(operation)
    }

    public struct Configuration: Sendable {
        public var provider: Provider?
        public var executablePath: String?
        public var model: String?
        public var workingDirectory: URL?
        public var extraArguments: [String]
        public var metadata: AgenticExecutionMetadata.Fields

        public init(
            provider: Provider? = nil,
            executablePath: String? = nil,
            model: String? = nil,
            workingDirectory: URL? = nil,
            extraArguments: [String] = [],
            metadata: AgenticExecutionMetadata.Fields = []
        ) {
            self.provider = provider
            self.executablePath = executablePath
            self.model = model
            self.workingDirectory = workingDirectory
            self.extraArguments = extraArguments
            self.metadata = metadata
        }
    }
}
