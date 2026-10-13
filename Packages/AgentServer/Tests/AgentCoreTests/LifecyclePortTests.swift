import Foundation
import Testing

@testable import AgentCore

#if os(macOS) || os(Linux)
private actor PortFixtureCompiler {
    static let shared = PortFixtureCompiler()
    private var build: Task<URL, any Error>?
    func executable() async throws -> URL {
        if let build { return try await build.value }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/PortListenerFixture.swift")
        let task = Task<URL, any Error> {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentServerPortFixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let executable = root.appendingPathComponent("port-listener")
            _ = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["swiftc", "-module-cache-path", root.appendingPathComponent("cache").path,
                            source.path, "-o", executable.path], timeoutSeconds: 120)
            return executable
        }
        build = task
        return try await task.value
    }
}

@Test func startReclaimsOccupiedTargetPort() async throws {
    try await withOwnedListener { port, child in
        let instance = try await ServerInstance.start(port: port, timeoutSeconds: 5)
        #expect(ServerInstance.isPortAvailable(port))
        child.waitUntilExit()
        withExtendedLifetime(instance) {}
    }
}

@Test func nonReplacingStartupNeverReclaimsAnOccupiedPort() async throws {
    try await withOwnedListener { port, child in
        let instance = try await ServerInstance.start(port: port, timeoutSeconds: 5, replaceExisting: false)
        #expect(child.isRunning)
        #expect(!ServerInstance.isPortAvailable(port))
        withExtendedLifetime(instance) {}
    }
}

private func withOwnedListener(operation: (Int, Process) async throws -> Void) async throws {
    let executable = try await PortFixtureCompiler.shared.executable()
    let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let configuration = try ServerConfiguration(environment: ["AGENT_SERVER_ENV": "testing"], workingDirectory: packageRoot)
    try await TestingPortAllocator.withAvailablePort(configuration: configuration.testingPorts) { port in
        let child = Process()
        let output = Pipe()
        child.executableURL = executable
        child.arguments = [String(port)]
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        try child.run()
        defer {
            if child.isRunning { child.terminate() }
            child.waitUntilExit()
        }
        // The fixture emits exactly one readiness line or exits immediately.
        let ready = output.fileHandleForReading.availableData
        if ready.isEmpty {
            child.waitUntilExit()
            if child.terminationStatus == 98 { throw TestingPortAllocator.AllocationError.portInUse }
            throw AgentError("fixture_startup_failed", "The owned port listener did not start.")
        }
        try await operation(port, child)
    }
}
#endif
