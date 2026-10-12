import AgentCore
import Foundation
import Testing

@Test func defaultsBindToLoopback() throws {
    let configuration = try ServerConfiguration(environment: [:])
    #expect(configuration.host == "127.0.0.1")
    #expect(configuration.port == 8080)
    #expect(configuration.shutdownTimeoutSeconds == 900)
    #expect(configuration.agentsDirectory.lastPathComponent == "Agents")
}

@Test func readsCentralConfigurationAndEnvironmentOverrides() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("server.json")
    try Data("{\"port\":9091,\"agents_directory\":\"Definitions\",\"shutdown_timeout_seconds\":900}".utf8)
        .write(to: file)
    let configuration = try ServerConfiguration(
        environment: ["AGENT_SERVER_CONFIG": file.path], workingDirectory: directory)
    #expect(configuration.port == 9091)
    #expect(configuration.agentsDirectory.path == directory.appendingPathComponent("Definitions").path)
    #expect(configuration.shutdownTimeoutSeconds == 900)
    let override = try ServerConfiguration(
        environment: ["AGENT_SERVER_CONFIG": file.path, "AGENT_SERVER_PORT": "8080"],
        workingDirectory: directory)
    #expect(override.port == 8080)
}

@Test func rejectsMissingExplicitConfiguration() {
    #expect(throws: ServerConfiguration.ConfigurationError.self) {
        try ServerConfiguration(environment: ["AGENT_SERVER_CONFIG": "/nonexistent/agentserver.json"])
    }
}

@Test func configurablePortAndAgentStorage() throws {
    let configuration = try ServerConfiguration(environment: [
        "AGENT_SERVER_PORT": "9090", "AGENT_SERVER_AGENTS_DIR": "/tmp/custom-agents",
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
