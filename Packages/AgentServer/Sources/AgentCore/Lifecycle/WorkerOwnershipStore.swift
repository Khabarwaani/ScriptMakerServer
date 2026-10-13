import Foundation

struct ProcessIdentity: Codable, Sendable, Equatable {
    let pid: Int32
    let parentPID: Int32
    let group: Int32
    let user: UInt32
    let birth: String
    let executable: String
    func matches(_ other: ProcessIdentity?) -> Bool {
        guard let other else { return false }
        return pid == other.pid && user == other.user && birth == other.birth && executable == other.executable
    }
}

/// A private per-port manifest is trusted only for identities captured while the
/// process was our child. Restart cleanup never relies on a stale PID alone.
public final class WorkerOwnershipStore: @unchecked Sendable {
    struct Record: Codable, Sendable {
        let owner: ProcessIdentity
        let worker: ProcessIdentity
    }
    public struct CleanupReport: Sendable {
        public let terminated: Int
        public let preserved: Int
    }
    private let url: URL
    private let lock = NSLock()
    private var records: [Record]
    private let inspect: @Sendable (Int32) -> ProcessIdentity?
    private let exists: @Sendable (Int32) -> Bool
    private let signal: @Sendable (ProcessIdentity, Bool) -> Bool

    public static func fileURL(port: Int) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Khabarwaani-AgentServer", isDirectory: true)
            .appendingPathComponent("workers-\(port).json")
    }
    public convenience init(url: URL) throws {
        try self.init(url: url, inspect: ProcessIdentity.inspect, exists: ProcessIdentity.exists,
                      signal: ProcessIdentity.signal)
    }
    init(
        url: URL, inspect: @escaping @Sendable (Int32) -> ProcessIdentity?,
        exists: @escaping @Sendable (Int32) -> Bool,
        signal: @escaping @Sendable (ProcessIdentity, Bool) -> Bool
    ) throws {
        self.url = url
        self.inspect = inspect
        self.exists = exists
        self.signal = signal
        let root = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard try Self.secure(root, type: .typeDirectory) else { throw Self.unavailable }
        if FileManager.default.fileExists(atPath: url.path) {
            guard try Self.secure(url, type: .typeRegular),
                (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 1_048_576
            else { throw Self.unavailable }
            do { records = try JSONDecoder().decode([Record].self, from: Data(contentsOf: url)) }
            catch { throw Self.unavailable }
            guard records.count <= 256, Set(records.map { $0.worker.pid }).count == records.count, records.allSatisfy({
                $0.worker.pid > 1 && $0.owner.pid > 1 && $0.worker.user == $0.owner.user
                    && $0.worker.parentPID == $0.owner.pid
                    && !$0.worker.birth.isEmpty && !$0.worker.executable.isEmpty
            }) else { throw Self.unavailable }
        } else { records = [] }
    }
    private static var unavailable: AgentError {
        AgentError("worker_ownership_unavailable", "The private worker ownership manifest could not be verified or written.")
    }
    private static func secure(_ url: URL, type: FileAttributeType) throws -> Bool {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let symbolic = try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink ?? true
        return attributes[.type] as? FileAttributeType == type
            && (attributes[.posixPermissions] as? Int ?? 0o777) & 0o077 == 0
            && (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == ProcessIdentity.currentUser
            && !symbolic && (type != .typeRegular || (attributes[.referenceCount] as? Int ?? 1) == 1)
    }
    private func persist() throws {
        let data = try JSONEncoder().encode(records)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func register(_ pid: Int32) throws {
        guard let owner = inspect(ProcessIdentity.currentPID), let worker = inspect(pid),
            worker.parentPID == owner.pid, worker.user == owner.user
        else { throw Self.unavailable }
        lock.lock()
        defer { lock.unlock() }
        guard records.count < 256 else { throw Self.unavailable }
        records.append(Record(owner: owner, worker: worker))
        do { try persist() } catch {
            records.removeLast()
            throw Self.unavailable
        }
    }
    func unregister(_ pid: Int32) {
        lock.lock()
        defer { lock.unlock() }
        records.removeAll { $0.worker.pid == pid }
        // A failed write leaves stale identities, which are re-verified at restart.
        do { try persist() } catch { print("AgentServer: worker_ownership_manifest_write_failed") }
    }
    func refresh(_ pid: Int32) {
        guard let current = inspect(pid) else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let index = records.firstIndex(where: {
            $0.worker.pid == pid && $0.worker.birth == current.birth && $0.worker.user == current.user
                && $0.owner.pid == current.parentPID && $0.owner.matches(inspect($0.owner.pid))
        }) else { return }
        // A configured shell/interpreter wrapper may exec the actual CLI after
        // launch. Only a still-owned process with unchanged birth can refresh.
        records[index] = Record(owner: records[index].owner, worker: current)
        do { try persist() } catch { print("AgentServer: worker_ownership_manifest_write_failed") }
    }
    private func storedRecords() -> [Record] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }
    private func replace(_ value: [Record]) throws {
        lock.lock()
        defer { lock.unlock() }
        records = value
        try persist()
    }
    /// Call only after acquiring the same port's ServerInstance lock.
    public func cleanupAfterRestart(graceSeconds: Double = 5) async throws -> CleanupReport {
        var preserved: [Record] = []
        var terminated = 0
        for record in storedRecords() {
            guard exists(record.worker.pid) else { continue }
            // The old owner may be a different still-running instance. Unknown
            // ownership or an identity mismatch is preserved, never signalled.
            let ownerStillExists = exists(record.owner.pid)
            let owner = inspect(record.owner.pid)
            guard record.worker.matches(inspect(record.worker.pid)),
                !(ownerStillExists && (owner == nil || record.owner.matches(owner)))
            else { preserved.append(record); continue }
            guard signal(record.worker, true) else { preserved.append(record); continue }
            let deadline = ContinuousClock.now.advanced(by: .seconds(graceSeconds))
            while record.worker.matches(inspect(record.worker.pid)) && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            if record.worker.matches(inspect(record.worker.pid)) {
                guard signal(record.worker, false) else { preserved.append(record); continue }
                let killDeadline = ContinuousClock.now.advanced(by: .seconds(5))
                while record.worker.matches(inspect(record.worker.pid)) && ContinuousClock.now < killDeadline {
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
            if record.worker.matches(inspect(record.worker.pid)) { preserved.append(record) }
            else { terminated += 1 }
        }
        try replace(preserved)
        return CleanupReport(terminated: terminated, preserved: preserved.count)
    }
}
