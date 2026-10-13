import Foundation
import Testing

@testable import AgentCore

private final class ProcessTable: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int32: ProcessIdentity] = [:]
    private var signals: [Int32] = []
    func put(_ identity: ProcessIdentity) { lock.withLock { values[identity.pid] = identity } }
    func remove(_ pid: Int32) { lock.withLock { values[pid] = nil } }
    func inspect(_ pid: Int32) -> ProcessIdentity? { lock.withLock { values[pid] } }
    func exists(_ pid: Int32) -> Bool { lock.withLock { values[pid] != nil } }
    var signalled: [Int32] { lock.withLock { signals } }
    func signal(_ identity: ProcessIdentity, _ graceful: Bool) -> Bool {
        lock.withLock {
            guard identity.matches(values[identity.pid]) else { return false }
            signals.append(identity.pid)
            values[identity.pid] = nil
            return true
        }
    }
}

@Test func restartCleanupKillsOnlyVerifiedOwnedWorkers() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let owner = try #require(ProcessIdentity.inspect(ProcessIdentity.currentPID))
    let table = ProcessTable()
    table.put(owner)
    let one = ProcessIdentity(pid: 700001, parentPID: owner.pid, group: 700001, user: owner.user, birth: "first", executable: "/provider")
    let two = ProcessIdentity(pid: 700002, parentPID: owner.pid, group: 700002, user: owner.user, birth: "original", executable: "/provider")
    table.put(one); table.put(two)
    let url = root.appendingPathComponent("workers.json")
    let store = try WorkerOwnershipStore(url: url, inspect: table.inspect, exists: table.exists, signal: table.signal)
    try store.register(one.pid); try store.register(two.pid)
    table.remove(owner.pid)
    // Same PID/executable, different birth: this is an unrelated replacement.
    table.put(ProcessIdentity(pid: two.pid, parentPID: 1, group: two.pid, user: owner.user, birth: "reused", executable: "/provider"))
    let restored = try WorkerOwnershipStore(url: url, inspect: table.inspect, exists: table.exists, signal: table.signal)
    let result = try await restored.cleanupAfterRestart(graceSeconds: 0)
    #expect(result.terminated == 1 && result.preserved == 1)
    #expect(table.signalled == [one.pid])
    #expect(table.exists(two.pid))
}

@Test func restartCleanupPreservesWorkersOfALiveOwnerAndRejectsForeignRegistration() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let owner = try #require(ProcessIdentity.inspect(ProcessIdentity.currentPID))
    let table = ProcessTable(); table.put(owner)
    let worker = ProcessIdentity(pid: 700003, parentPID: owner.pid, group: 700003, user: owner.user, birth: "owned", executable: "/provider")
    let foreign = ProcessIdentity(pid: 700004, parentPID: 1, group: 700004, user: owner.user, birth: "foreign", executable: "/provider")
    table.put(worker); table.put(foreign)
    let store = try WorkerOwnershipStore(url: root.appendingPathComponent("workers.json"), inspect: table.inspect, exists: table.exists, signal: table.signal)
    try store.register(worker.pid)
    #expect(throws: AgentError.self) { try store.register(foreign.pid) }
    let result = try await store.cleanupAfterRestart(graceSeconds: 0)
    #expect(result.terminated == 0 && result.preserved == 1 && table.signalled.isEmpty)
}

@Test func ownershipManifestRejectsMalformedAndSymlinkedFiles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("workers.json")
    try Data("not valid JSON".utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    #expect(throws: AgentError.self) { try WorkerOwnershipStore(url: file) }
    let link = root.appendingPathComponent("link.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    #expect(throws: AgentError.self) { try WorkerOwnershipStore(url: link) }
}

@Test func launchedProcessesAreJournaledAndRemovedAfterExit() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("workers.json")
    let store = try WorkerOwnershipStore(url: url)
    let runner = ProcessRunner(ownership: store)
    let task = Task { try await runner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeoutSeconds: 60) }
    for _ in 0..<200 { if runner.processID != nil && FileManager.default.fileExists(atPath: url.path) { break }; try await Task.sleep(for: .milliseconds(10)) }
    let records = try JSONDecoder().decode([WorkerOwnershipStore.Record].self, from: Data(contentsOf: url))
    #expect(records.count == 1 && records.first?.worker.parentPID == ProcessIdentity.currentPID)
    runner.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try JSONDecoder().decode([WorkerOwnershipStore.Record].self, from: Data(contentsOf: url)).isEmpty)
}

@Test func ownedWrapperExecCanRefreshButPIDReuseCannot() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let owner = try #require(ProcessIdentity.inspect(ProcessIdentity.currentPID))
    let table = ProcessTable(); table.put(owner)
    let pid: Int32 = 700005
    let wrapper = ProcessIdentity(pid: pid, parentPID: owner.pid, group: pid, user: owner.user, birth: "owned", executable: "/wrapper")
    table.put(wrapper)
    let url = root.appendingPathComponent("workers.json")
    let store = try WorkerOwnershipStore(url: url, inspect: table.inspect, exists: table.exists, signal: table.signal)
    try store.register(pid)
    table.put(ProcessIdentity(pid: pid, parentPID: owner.pid, group: pid, user: owner.user, birth: "owned", executable: "/provider"))
    store.refresh(pid)
    #expect(try JSONDecoder().decode([WorkerOwnershipStore.Record].self, from: Data(contentsOf: url)).first?.worker.executable == "/provider")
    table.put(ProcessIdentity(pid: pid, parentPID: owner.pid, group: pid, user: owner.user, birth: "unrelated", executable: "/other"))
    store.refresh(pid)
    table.remove(owner.pid)
    let result = try await store.cleanupAfterRestart(graceSeconds: 0)
    #expect(result.preserved == 1 && table.signalled.isEmpty)
    // Once that PID represents a newly verified child, registration replaces
    // the stale entry and the manifest remains decodable after restart.
    table.put(owner)
    try store.register(pid)
    let records = try JSONDecoder().decode([WorkerOwnershipStore.Record].self, from: Data(contentsOf: url))
    #expect(records.count == 1 && records.first?.worker.birth == "unrelated")
    _ = try WorkerOwnershipStore(url: url, inspect: table.inspect, exists: table.exists, signal: table.signal)
}

@Test func shortReadinessChildrenNeedNoLiveOwnershipRecord() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorkerOwnershipStore(url: root.appendingPathComponent("workers.json"))
    for _ in 0..<20 {
        _ = try await ProcessRunner(ownership: store).run(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [], timeoutSeconds: 5)
    }
}
