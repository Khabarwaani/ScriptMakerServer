import Foundation
import AgentAtom

/// Common configuration shared across all terminal CLI agent sessions.
public struct TerminalAgentConfiguration: Sendable, Equatable {
    /// The executable name or absolute file path to the CLI binary.
    public var executablePath: String
    /// Optional model identifier override (e.g. `gpt-4o`, `gemini-1.5-pro`, `grok-beta`).
    public var model: String?
    /// Working directory for subprocess execution.
    public var workingDirectory: URL?
    /// Additional CLI arguments passed directly to the tool.
    public var extraArguments: [String]
    /// Metadata tracking preferences.
    public var metadata: AgenticExecutionMetadata.Fields
    /// Pre-resolved URL of the binary, computed on initialization.
    var resolvedURL: URL?

    public init(
        executablePath: String,
        model: String? = nil,
        workingDirectory: URL? = nil,
        extraArguments: [String] = [],
        metadata: AgenticExecutionMetadata.Fields = []
    ) {
        self.executablePath = executablePath
        self.model = model
        self.workingDirectory = workingDirectory
        self.extraArguments = extraArguments
        self.metadata = metadata
        self.resolvedURL = nil
    }
}
