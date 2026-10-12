import Foundation

/// Small JSONL state snapshots on disk, never provider output or request bodies.
/// One server instance owns this file; its instance lock must be acquired first.
public final class ExecutionSessionLog: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()
    private let writer: FileHandle
    private var failure: AgentError?

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        // A fresh server session replaces the previous session's log.
        try Data().write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        writer = try FileHandle(forWritingTo: url)
    }

    deinit { try? writer.close() }

    func append(_ record: ExecutionRecord) {
        lock.lock()
        defer { lock.unlock() }
        guard failure == nil else { return }
        do {
            var compact = record
            compact.retainOnlyStateTimingAndError()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            var data = try encoder.encode(compact)
            data.append(10)
            try writer.write(contentsOf: data)
        } catch {
            failure = AgentError("execution_log_unavailable", "The session execution log could not be written. Check temporary-directory permissions and disk space.")
            print("AgentServer: execution_log_unavailable")
        }
    }

    /// Read a bounded tail instead of loading the full session file into memory.
    public func recentRecords() throws -> [ExecutionRecord] {
        lock.lock()
        defer { lock.unlock() }
        if let failure { throw failure }
        let reader = try FileHandle(forReadingFrom: url)
        defer { try? reader.close() }
        var offset = try reader.seekToEnd()
        var tail = Data()
        var newlines = 0
        while offset > 0 && newlines <= 200 && tail.count < 2_097_152 {
            let size = min(offset, 8192)
            offset -= size
            try reader.seek(toOffset: offset)
            let chunk = try reader.read(upToCount: Int(size)) ?? Data()
            newlines += chunk.filter { $0 == 10 }.count
            tail.insert(contentsOf: chunk, at: 0)
        }
        var lines = tail.split(separator: 10)
        if offset > 0 && !lines.isEmpty { lines.removeFirst() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try lines.suffix(200).map { try decoder.decode(ExecutionRecord.self, from: Data($0)) }
    }

    public func snapshotFile() throws -> (url: URL, length: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        if let failure { throw failure }
        return (url, try writer.offset())
    }
}
