import AgentCore
import Foundation
import Testing

@Test func defaultsBindToLoopback() throws {
    let configuration = try ServerConfiguration(environment: [:])
    #expect(configuration.host == "127.0.0.1")
    #expect(configuration.port == 8080)
    #expect(configuration.shutdownTimeoutSeconds == 900)
    #expect(configuration.providerPoolSize == 5)
    #expect(configuration.agentsDirectory.lastPathComponent == "Agents")
}

@Test(arguments: [-1, 9]) func rejectsPoolSizeOutsideTotalLimit(size: Int) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("server.json")
    try Data("{\"provider_pool_size\":\(size),\"max_processes\":8}".utf8).write(to: file)
    #expect(throws: ServerConfiguration.ConfigurationError.self) {
        try ServerConfiguration(environment: ["AGENT_SERVER_CONFIG": file.path])
    }
}

@Test(arguments: [0, 3, 8]) func readsGlobalPoolCapacity(size: Int) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("server.json")
    try Data("{\"provider_pool_size\":\(size),\"max_processes\":8}".utf8).write(to: file)
    let config = try ServerConfiguration(environment: ["AGENT_SERVER_CONFIG": file.path])
    #expect(config.providerPoolSize == size)
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

@Test func startReclaimsOccupiedTargetPort() async throws {
    let testPort = 19482
    let dummy = Process()
    dummy.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    dummy.arguments = [
        "-c",
        """
        import socket, time
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(("127.0.0.1", \(testPort)))
        s.listen(1)
        time.sleep(30)
        """
    ]
    try dummy.run()
    // Wait until dummy process is listening
    var ready = false
    for _ in 0..<30 {
        if !ServerInstance.isPortAvailable(testPort) {
            ready = true
            break
        }
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(ready)

    // Starting ServerInstance should reap the process on testPort and successfully acquire instance
    let instance = try await ServerInstance.start(port: testPort, timeoutSeconds: 5)
    #expect(ServerInstance.isPortAvailable(testPort) == true)
    dummy.waitUntilExit()
    withExtendedLifetime(instance) {}
}

