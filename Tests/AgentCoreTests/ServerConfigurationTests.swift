import AgentCore
import Foundation
import Testing

@Test func defaultsBindToLoopback() throws {
    let configuration = try ServerConfiguration(environment: [:])
    #expect(configuration.host == "127.0.0.1")
    #expect(configuration.port == 8080)
    #expect(configuration.agentsDirectory.lastPathComponent == "Agents")
}

@Test func configurablePortAndAgentStorage() throws {
    let configuration = try ServerConfiguration(environment: [
        "AGENT_SERVER_PORT": "9090", "AGENT_SERVER_AGENTS_DIR": "/tmp/custom-agents"
    ])
    #expect(configuration.port == 9090)
    #expect(configuration.agentsDirectory.path == "/tmp/custom-agents")
}

@Test(arguments: ["0", "65536", "invalid", "-1", ""])
func rejectsInvalidPorts(value: String) {
    #expect(throws: ServerConfiguration.ConfigurationError.self) {
        try ServerConfiguration(environment: ["AGENT_SERVER_PORT": value])
    }
}
