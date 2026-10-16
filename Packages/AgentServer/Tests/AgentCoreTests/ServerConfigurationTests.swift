import AgentCore
import Foundation
import Testing

@Test func defaultsBindToLoopback() throws {
    let configuration = try ServerConfiguration(environment: [:])
    #expect(configuration.host == "127.0.0.1")
    #expect(configuration.port == 8080)
    #expect(configuration.serverEnvironment == .development)
    #expect(configuration.shutdownTimeoutSeconds == 900)
    #expect(configuration.providerPoolSize == 5)
    #expect(configuration.queueTimeoutSeconds == 30)
    #expect(configuration.agentsDirectory.lastPathComponent == "Agents")
}

@Test func environmentSpecificPortDefaults() throws {
    let production = try ServerConfiguration(environment: ["AGENT_SERVER_ENV": "production"])
    #expect(production.port == 8081)
    let testing = try ServerConfiguration(environment: ["AGENT_SERVER_ENV": "testing"])
    #expect(testing.port == nil)
    #expect(testing.testingPorts.range == 9000...9999)
    #expect(testing.testingPorts.maxAttempts == 30)
}

@Test func readsEnvironmentPortConfigurationAndOverrides() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("server.json")
    try Data("""
        {"environment":"production","ports":{"production":8181,"development":8180,
        "testing":{"min":9200,"max":9299,"max_attempts":10}}}
        """.utf8).write(to: file)
    let base = ["AGENT_SERVER_CONFIG": file.path]
    #expect(try ServerConfiguration(environment: base).port == 8181)
    let testing = try ServerConfiguration(environment: base.merging(["AGENT_SERVER_ENV": "testing"]) { _, new in new })
    #expect(testing.port == nil)
    #expect(testing.testingPorts.range == 9200...9299)
    #expect(testing.testingPorts.maxAttempts == 10)
    let override = try ServerConfiguration(environment: base.merging([
        "AGENT_SERVER_ENV": "testing", "AGENT_SERVER_PORT": "9205"
    ]) { _, new in new })
    #expect(override.port == 9205)
    #expect(throws: ServerConfiguration.ConfigurationError.self) {
        try ServerConfiguration(environment: base.merging([
            "AGENT_SERVER_ENV": "testing", "AGENT_SERVER_PORT": "8080"
        ]) { _, new in new })
    }
}

@Test(arguments: ["invalid", "", "test"])
func rejectsInvalidServerEnvironment(value: String) {
    #expect(throws: ServerConfiguration.ConfigurationError.self) {
        try ServerConfiguration(environment: ["AGENT_SERVER_ENV": value])
    }
}

@Test(arguments: [
    "{\"production\":8080,\"development\":8080}",
    "{\"production\":0}",
    "{\"development\":9000}",
    "{\"testing\":{\"min\":0}}",
    "{\"testing\":{\"min\":9999,\"max\":9000}}",
    "{\"testing\":{\"max\":65536}}",
    "{\"testing\":{\"max_attempts\":0}}",
    "{\"testing\":{\"max_attempts\":31}}"
])
func rejectsInvalidEnvironmentPortSettings(ports: String) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("server.json")
    try Data("{\"ports\":\(ports)}".utf8).write(to: file)
    #expect(throws: ServerConfiguration.ConfigurationError.self) {
        try ServerConfiguration(environment: ["AGENT_SERVER_CONFIG": file.path])
    }
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
    try Data("{\"port\":8091,\"agents_directory\":\"Definitions\",\"shutdown_timeout_seconds\":900}".utf8)
        .write(to: file)
    let configuration = try ServerConfiguration(
        environment: ["AGENT_SERVER_CONFIG": file.path], workingDirectory: directory)
    #expect(configuration.port == 8091)
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
        "AGENT_SERVER_PORT": "8090", "AGENT_SERVER_AGENTS_DIR": "/tmp/custom-agents",
    ])
    #expect(configuration.port == 8090)
    #expect(configuration.agentsDirectory.path == "/tmp/custom-agents")
}

@Test(arguments: [
    ["AGENT_SERVER_ENV": "production", "AGENT_SERVER_PORT": "8080"],
    ["AGENT_SERVER_ENV": "development", "AGENT_SERVER_PORT": "8081"],
    ["AGENT_SERVER_ENV": "development", "AGENT_SERVER_PORT": "9000"],
    ["AGENT_SERVER_ENV": "production", "AGENT_SERVER_PORT": "9999"],
    ["AGENT_SERVER_ENV": "testing", "AGENT_SERVER_PORT": "8080"]
])
func portOverridesCannotCrossEnvironmentBoundaries(environment: [String: String]) {
    #expect(throws: ServerConfiguration.ConfigurationError.self) {
        try ServerConfiguration(environment: environment)
    }
}

@Test(arguments: ["0", "65536", "invalid", "-1", ""])
func rejectsInvalidPorts(value: String) {
    #expect(throws: ServerConfiguration.ConfigurationError.self) {
        try ServerConfiguration(environment: ["AGENT_SERVER_PORT": value])
    }
}


@Test(arguments: [0, 1, 30, 300, 301])
func validatesQueueTimeoutConfiguration(seconds: Int) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("server.json")
    try Data("{\"queue_timeout_seconds\":\(seconds)}".utf8).write(to: file)
    if (1...300).contains(seconds) {
        #expect(try ServerConfiguration(environment: ["AGENT_SERVER_CONFIG": file.path]).queueTimeoutSeconds == seconds)
    } else {
        #expect(throws: ServerConfiguration.ConfigurationError.self) {
            try ServerConfiguration(environment: ["AGENT_SERVER_CONFIG": file.path])
        }
    }
}
