import Foundation
import Testing

@testable import AgentCore

@Test func sessionLogsTrackOutcomesWithoutInputAndResetOnRestart() async throws {
    let fixture = try AgentFixture()
    let url = fixture.directory.appendingPathComponent("logs/executions.jsonl")
    let log = try ExecutionSessionLog(url: url)
    let manager = makeManager(fixture, sessionLog: log)
    let success = try await manager.execute(request("private-request-and-result"))
    _ = await events(success)
    let failureManager = makeManager(fixture, provider: MockProvider(fail: true), sessionLog: log)
    let failure = try await failureManager.execute(request("private-request-and-result"))
    _ = await events(failure)
    let records = try await manager.recentExecutionLogs()
    #expect(records.filter { $0.execution_id == success.id }.map(\.status) == ["queued", "running", "completed"])
    #expect(records.filter { $0.execution_id == failure.id }.map(\.status) == ["queued", "running", "failed"])
    let failed = try #require(records.last)
    #expect(failed.error?.code == "provider_execution_failed")
    #expect(failed.error?.message == "Mock provider failed.")
    #expect(failed.ended_at != nil && failed.running_at != nil)
    #expect(!String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("private-request-and-result"))
    #expect(records.allSatisfy { $0.agent_id == nil && $0.provider == nil && $0.process_id == nil })
    await manager.shutdown(timeoutSeconds: 1)
    await failureManager.shutdown(timeoutSeconds: 1)
    #expect(await manager.snapshot().records.isEmpty)
    #expect(try log.recentRecords().count == 6)
    let restartedLog = try ExecutionSessionLog(url: url)
    #expect(try restartedLog.recentRecords().isEmpty)
    #expect(try restartedLog.snapshotFile().length == 0)
}

@Test func sessionLogTailAndRetainedErrorsAreBounded() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let log = try ExecutionSessionLog(url: root.appendingPathComponent("executions.jsonl"))
    for index in 0..<210 {
        var record = ExecutionRecord(execution_id: "exec_\(index)", status: "failed", started_at: Date())
        record.error = AgentError(String(repeating: "c", count: 200), String(repeating: "d", count: 5000))
        record.retainOnlyStateTimingAndError()
        #expect(record.error?.code.count == 128 && record.error?.message.count == 1024)
        log.append(record)
    }
    let tail = try log.recentRecords()
    #expect(tail.count == 200 && tail.first?.execution_id == "exec_10" && tail.last?.execution_id == "exec_209")
    let permissions = try FileManager.default.attributesOfItem(atPath: log.url.path)[.posixPermissions] as? Int
    #expect(permissions == 0o600)
}
