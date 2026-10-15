import Foundation
import Testing
import AgentAtom
@testable import TerminalAgentSession

// Simple ModelledSpec for testing
struct MockEchoSpec: ModelledSpec {
    struct Input: Codable, Sendable {
        let message: String
    }

    struct Output: Codable, Sendable, Equatable {
        let reply: String
    }

    static var identity: Identity { Identity(id: "MockEcho", name: "MockEcho", version: "1.0.0") }
    static var role: String { "Mock assistant" }
    var instructions: String { "Echo the message in reply" }

    var input: Input
    var output: Output?

    init(message: String) {
        self.input = Input(message: message)
    }
}

@Suite("TerminalAgentSession Tests")
struct TerminalSessionTests {
    private func createMockExecutable(script: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("mock_cli_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let scriptURL = tempDir.appendingPathComponent("mock_tool.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let permissions: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
        try FileManager.default.setAttributes(permissions, ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    @Test("CodexTerminalSession executes and decodes successfully via ModelledSpec convenience")
    func testCodexSessionConvenienceExecute() async throws {
        // Mock Codex script that writes to -o output argument
        let script = """
        #!/bin/bash
        # Parse arguments to find output path (-o)
        while [[ "$#" -gt 0 ]]; do
            case $1 in
                -o) output_file="$2"; shift ;;
            esac
            shift
        done
        echo '{"reply":"Hello from Codex"}' > "$output_file"
        exit 0
        """
        let scriptURL = try createMockExecutable(script: script)
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

        let config = CodexTerminalSession.Configuration(executablePath: scriptURL.path)
        guard let session = CodexTerminalSession(configuration: config) else {
            Issue.record("Failed to initialize CodexTerminalSession with mock script")
            return
        }

        let spec = MockEchoSpec(message: "Hi")
        let output = try await session.execute(spec)
        #expect(output.reply == "Hello from Codex")
    }

    @Test("AntigravityTerminalSession streams and decodes successfully via ModelledSpec convenience")
    func testAntigravitySessionStreamingAndExecute() async throws {
        // Mock Antigravity script that outputs stream-json format
        let script = """
        #!/bin/bash
        echo '{"type":"text","content":"Generating response..."}'
        echo '{"type":"result","response":"{\\"reply\\":\\"Hello from Antigravity\\"}"}'
        exit 0
        """
        let scriptURL = try createMockExecutable(script: script)
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

        let config = AntigravityTerminalSession.Configuration(executablePath: scriptURL.path)
        guard let session = AntigravityTerminalSession(configuration: config) else {
            Issue.record("Failed to initialize AntigravityTerminalSession with mock script")
            return
        }

        let spec = MockEchoSpec(message: "Hi")
        let output = try await session.execute(spec)
        #expect(output.reply == "Hello from Antigravity")
    }

    @Test("GrokTerminalSession streams and decodes successfully via typed respond convenience")
    func testGrokSessionTypedRespond() async throws {
        // Mock Grok script that outputs streaming-messages-json format
        let script = """
        #!/bin/bash
        echo '{"delta":"Thinking..."}'
        echo '{"result":"{\\"reply\\":\\"Hello from Grok\\"}"}'
        exit 0
        """
        let scriptURL = try createMockExecutable(script: script)
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

        let config = GrokTerminalSession.Configuration(executablePath: scriptURL.path)
        guard let session = GrokTerminalSession(configuration: config) else {
            Issue.record("Failed to initialize GrokTerminalSession with mock script")
            return
        }

        let output: MockEchoSpec.Output = try await session.respond(
            input: MockEchoSpec.Input(message: "Hi"),
            instructions: "Echo"
        )
        #expect(output.reply == "Hello from Grok")
    }


    @Test("TerminalAgentSession provider explicit selection and custom provider registration")
    func testTerminalAgentSessionProviderSelection() throws {
        let script = """
        #!/bin/bash
        echo '{"reply":"Selected Provider"}'
        """
        let scriptURL = try createMockExecutable(script: script)
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

        let config = TerminalAgentConfiguration(executablePath: scriptURL.path)

        // Custom provider from another imaginary package or custom CLI
        let customProvider = TerminalProvider(name: "custom", defaultExecutablePath: scriptURL.path) {
            AntigravityTerminalSession(configuration: $0)
        }

        let session = TerminalAgentSession(provider: customProvider, configuration: config)
        #expect(session != nil)

        // Verify generic one-liner session for any current/future CLI tool (e.g. "muse")
        let museSession = TerminalAgentSession(executablePath: scriptURL.path)
        #expect(museSession != nil)
        let genericDirectSession = GenericTerminalSession(executablePath: scriptURL.path)
        #expect(genericDirectSession != nil)

        // Verify TerminalSessionProtocol polymorphism across all sessions
        let terminalSessions: [any TerminalSessionProtocol] = [
            session!,
            museSession!,
            genericDirectSession!,
            AntigravityTerminalSession(configuration: config)!,
            CodexTerminalSession(configuration: config)!,
            GrokTerminalSession(configuration: config)!
        ]
        #expect(terminalSessions.count == 6)
        for s in terminalSessions {
            #expect(!s.configuration.executablePath.isEmpty)
        }
    }

    @Test("Process exit failure maps cleanly to AgenticError.operationFailed")
    func testProcessFailureMapping() async throws {
        let script = """
        #!/bin/bash
        >&2 echo "Critical syntax error or failure"
        exit 1
        """
        let scriptURL = try createMockExecutable(script: script)
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

        let config = CodexTerminalSession.Configuration(executablePath: scriptURL.path)
        guard let session = CodexTerminalSession(configuration: config) else {
            Issue.record("Failed to initialize session")
            return
        }

        let spec = MockEchoSpec(message: "Hi")
        await #expect(throws: AgenticError.self) {
            try await session.execute(spec)
        }
    }

    @Test("StreamingAgenticOperation streams tokens and finishes with final decoded value")
    func testStreamingOperationExecution() async throws {
        let script = """
        #!/bin/bash
        echo '{"type":"text","content":"Token1"}'
        sleep 0.02
        echo '{"type":"text","content":"Token2"}'
        sleep 0.02
        echo '{"type":"result","response":"{\\"reply\\":\\"Done\\"}"}'
        exit 0
        """
        let scriptURL = try createMockExecutable(script: script)
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

        let config = AntigravityTerminalSession.Configuration(executablePath: scriptURL.path)
        guard let session = AntigravityTerminalSession(configuration: config) else {
            Issue.record("Failed to initialize session")
            return
        }

        let spec = MockEchoSpec(message: "Hi")
        let streamOp = StreamingAgenticOperation(spec: spec, session: session)
        var streamedChunks: [String] = []

        for await event in await streamOp.execute() {
            if case .success(let text) = event {
                streamedChunks.append(text)
            }
        }

        #expect(streamedChunks.contains("Token1"))
        #expect(streamedChunks.contains("Token2"))
        #expect(streamedChunks.contains("{\"reply\":\"Done\"}"))
    }

    @Test("TerminalSession tracks execution metadata and clearMemory resets it")
    func testContextPreservationAcrossTurns() async throws {
        let script = """
        #!/bin/bash
        echo "{\\"reply\\":\\"Seen Turn\\"}"
        exit 0
        """
        let scriptURL = try createMockExecutable(script: script)
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

        let config = TerminalAgentConfiguration(executablePath: scriptURL.path)
        let session = CodexTerminalSession(configuration: config)!

        // Turn 1
        _ = try await session.execute(MockEchoSpec(message: "My name is Alice"))

        // Turn 2
        _ = try await session.execute(MockEchoSpec(message: "What is my name?"))

        // Verify execution metadata recorded both turns
        #expect(session.executionMetadata.count == 2)

        // Clear memory explicitly
        session.clearMemory()
        #expect(session.executionMetadata.isEmpty)

        // Turn 3 starts with cleared memory
        _ = try await session.execute(MockEchoSpec(message: "Fresh start"))
        #expect(session.executionMetadata.count == 1)
    }

    @Test("TerminalSession discovers binaries in additionalSearchPaths")
    func testAdditionalSearchPathsDiscovery() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let customBinary = tempDir.appendingPathComponent("custom-agent-cli")
        let script = """
        #!/bin/bash
        echo "{\\"reply\\":\\"from custom path\\"}"
        """
        try script.write(to: customBinary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: customBinary.path)

        // Without additionalSearchPaths, resolving "custom-agent-cli" fails
        let configWithout = TerminalAgentConfiguration(executablePath: "custom-agent-cli")
        #expect(GenericTerminalSession(configuration: configWithout) == nil)

        // With additionalSearchPaths, resolving succeeds
        let configWith = TerminalAgentConfiguration(
            executablePath: "custom-agent-cli",
            additionalSearchPaths: [tempDir.path]
        )
        let session = GenericTerminalSession(configuration: configWith)
        #expect(session != nil)
    }
}

