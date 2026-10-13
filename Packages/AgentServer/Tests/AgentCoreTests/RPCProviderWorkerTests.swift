import Foundation
import Testing

@testable import AgentCore

private actor FixtureCompiler {
    static let shared = FixtureCompiler()
    private var build: Task<URL, any Error>?
    func executable() async throws -> URL {
        if let build { return try await build.value }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/ProviderRPCFixture.swift")
        let task = Task<URL, any Error> {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentServerRPCFixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let executable = root.appendingPathComponent("provider-fixture")
            _ = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["swiftc", "-module-cache-path", root.appendingPathComponent("cache").path, source.path, "-o", executable.path], timeoutSeconds: 120)
            return executable
        }
        build = task
        return try await task.value
    }
}

@Test(arguments: [CLIProvider.Kind.codex, .grok])
func nativeWorkersUseFreshContextsAndReleaseThem(kind: CLIProvider.Kind) async throws {
    let fixture = try AgentFixture()
    let executable = try await FixtureCompiler.shared.executable()
    let provider = CLIProvider(kind: kind, settings: .init(executable: executable.path))
    let worker = try provider.makeWorker(ownership: nil)
    let definition = try await AgentRegistry(packages: [EchoPackage.self], root: fixture.agents).resolve(id: "Echo", version: nil)
    var pid: Int32?
    for marker in ["first-private", "second"] {
        let value = try await worker.execute(definition: definition, input: .object(["text": .string(marker)]),
            directory: fixture.runtime, timeoutSeconds: 10, onOutput: { _ in }, onProgress: { _ in }, onPhase: { _, _ in })
        #expect(value == .object(["result": .string(marker)]))
        #expect(worker.runner.processID != nil)
        if let pid { #expect(worker.runner.processID == pid) } else { pid = worker.runner.processID }
        try await worker.reset()
        #expect(worker.reusable && worker.healthy)
    }
    await worker.shutdown()
    #expect(worker.runner.processID == nil && !worker.healthy)
}

@Test(arguments: [CLIProvider.Kind.codex, .grok])
func nativeResetFailureDisablesFutureReuseWithoutReplay(kind: CLIProvider.Kind) async throws {
    let fixture = try AgentFixture()
    let provider = CLIProvider(kind: kind, settings: .init(executable: try await FixtureCompiler.shared.executable().path))
    let worker = try provider.makeWorker(ownership: nil)
    let definition = try await AgentRegistry(packages: [EchoPackage.self], root: fixture.agents).resolve(id: "Echo", version: nil)
    _ = try await worker.execute(definition: definition, input: .object(["text": .string("reset-fail")]),
        directory: fixture.runtime, timeoutSeconds: 10, onOutput: { _ in }, onProgress: { _ in }, onPhase: { _, _ in })
    await #expect(throws: AgentError.self) { try await worker.reset() }
    await worker.shutdown()
    #expect(!worker.reusable && provider.workerReuseMode == "fresh:reset-unavailable")
    #expect(try !provider.makeWorker(ownership: nil).reusable)
}

@Test func nativeWorkerCrashUnblocksThePendingRequest() async throws {
    let fixture = try AgentFixture()
    let provider = CLIProvider(kind: .codex, settings: .init(executable: try await FixtureCompiler.shared.executable().path))
    let worker = try provider.makeWorker(ownership: nil)
    let definition = try await AgentRegistry(packages: [EchoPackage.self], root: fixture.agents).resolve(id: "Echo", version: nil)
    await #expect(throws: AgentError.self) {
        try await worker.execute(definition: definition, input: .object(["text": .string("crash")]),
            directory: fixture.runtime, timeoutSeconds: 10, onOutput: { _ in }, onProgress: { _ in }, onPhase: { _, _ in })
    }
    await worker.shutdown()
    #expect(worker.runner.processID == nil && !worker.healthy)
}

@Test func antigravityAndUnverifiedSettingsStayOnFreshProcesses() throws {
    let antigravity = CLIProvider(kind: .antigravity, settings: .init(executable: "agy"))
    #expect(try !antigravity.makeWorker(ownership: nil).reusable)
    let grok = CLIProvider(kind: .grok, settings: .init(executable: "grok", reasoningEffort: "low"))
    #expect(try !grok.makeWorker(ownership: nil).reusable)
    #expect(grok.workerReuseMode == "fresh:settings-unverified")
}

@Test(arguments: [CLIProvider.Kind.codex, .grok])
func cancellingNativeWorkersReapsTheirProcess(kind: CLIProvider.Kind) async throws {
    let fixture = try AgentFixture()
    let binary = try await FixtureCompiler.shared.executable()
    let shim = fixture.directory.appendingPathComponent("slow-provider")
    try Data("#!/bin/sh\nexec '\(binary.path)' --delay-result \"$@\"\n".utf8).write(to: shim)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: shim.path)
    let provider = CLIProvider(kind: kind, settings: .init(executable: shim.path))
    let worker = try provider.makeWorker(ownership: nil)
    let definition = try await AgentRegistry(packages: [EchoPackage.self], root: fixture.agents).resolve(id: "Echo", version: nil)
    let task = Task {
        try await worker.execute(definition: definition, input: .object(["text": .string("slow")]),
            directory: fixture.runtime, timeoutSeconds: 30, onOutput: { _ in }, onProgress: { _ in }, onPhase: { _, _ in })
    }
    for _ in 0..<200 {
        if worker.runner.timing.ready != nil { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(worker.runner.processID != nil)
    worker.runner.cancel()
    task.cancel()
    await worker.shutdown()
    await #expect(throws: (any Error).self) { try await task.value }
    #expect(worker.runner.processID == nil && !worker.healthy)
}

@Test func unsupportedResetFallsBackBeforeSendingInference() async throws {
    let fixture = try AgentFixture()
    try FileManager.default.createDirectory(at: fixture.runtime, withIntermediateDirectories: true)
    let binary = try await FixtureCompiler.shared.executable()
    let shim = fixture.directory.appendingPathComponent("old-provider")
    try Data("#!/bin/sh\nexec '\(binary.path)' --without-close \"$@\"\n".utf8).write(to: shim)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: shim.path)
    let provider = CLIProvider(kind: .grok, settings: .init(executable: shim.path))
    let worker = try provider.makeWorker(ownership: nil)
    let definition = try await AgentRegistry(packages: [EchoPackage.self], root: fixture.agents).resolve(id: "Echo", version: nil)
    let value = try await worker.execute(definition: definition, input: .object(["text": .string("fallback-only-once")]),
        directory: fixture.runtime, timeoutSeconds: 10, onOutput: { _ in }, onProgress: { _ in }, onPhase: { _, _ in })
    #expect(value == .object(["result": .string("fallback-only-once")]))
    #expect(!worker.reusable && provider.workerReuseMode == "fresh:reset-unavailable")
    await worker.shutdown()
    #expect(worker.runner.processID == nil)
}
