import Foundation
import AgentAtom

/// A protocol representing an `AgenticSessionProtocol` that is driven by a terminal CLI subprocess.
///
/// All concrete terminal session drivers (e.g. `CodexTerminalSession`, `AntigravityTerminalSession`,
/// `GrokTerminalSession`, and `TerminalAgentSession`) conform to `TerminalSessionProtocol`.
public protocol TerminalSessionProtocol: AgenticSessionProtocol {
    /// The configuration describing the binary path, arguments, working directory, and metadata.
    var configuration: TerminalAgentConfiguration { get }
}
