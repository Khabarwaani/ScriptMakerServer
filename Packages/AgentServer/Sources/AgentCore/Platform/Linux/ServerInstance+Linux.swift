#if os(Linux)
import Glibc
import Foundation

extension ServerInstance: LockPlatformDelegate {
    static func closePlatformDescriptor(_ descriptor: Int32) {
        close(descriptor)
    }

    static func openPlatformLock(port: Int) throws -> Int32 {
        let baseDir = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"]
            ?? FileManager.default.temporaryDirectory.path
        let root = URL(fileURLWithPath: baseDir).appendingPathComponent(
            "Khabarwaani-AgentServer", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var directoryInfo = stat()
        guard lstat(root.path, &directoryInfo) == 0,
            directoryInfo.st_uid == getuid(),
            directoryInfo.st_mode & S_IFMT == S_IFDIR,
            directoryInfo.st_mode & 0o077 == 0
        else {
            throw InstanceError.unsafeLockFile
        }
        let path = root.appendingPathComponent("port-\(port).lock").path
        let descriptor = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw InstanceError.unsafeLockFile }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
            info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
            info.st_nlink == 1, info.st_mode & 0o077 == 0
        else {
            close(descriptor)
            throw InstanceError.unsafeLockFile
        }
        return descriptor
    }

    static func applyPlatformWriteLock(descriptor: Int32) throws {
        var lock = writeLock()
        guard fcntl(descriptor, F_SETLK, &lock) == 0 else {
            throw InstanceError.concurrentStartup
        }
    }

    static func stopPlatformOwner(descriptor: Int32, timeoutSeconds: Int) async throws -> Bool {
        guard let pid = try owner(descriptor: descriptor) else { return false }
        var buffer = [CChar](repeating: 0, count: 4096)
        let linkLength = readlink("/proc/\(pid)/exe", &buffer, buffer.count - 1)
        guard linkLength > 0 else {
            if try owner(descriptor: descriptor) == nil { return true }
            throw InstanceError.unverifiedProcess
        }
        buffer[linkLength] = 0
        let path = String(cString: buffer)
        guard URL(fileURLWithPath: path).lastPathComponent == "AgentServer", pid != getpid() else {
            throw InstanceError.unverifiedProcess
        }
        guard try owner(descriptor: descriptor) == pid else { throw InstanceError.concurrentStartup }
        guard kill(pid, SIGTERM) == 0 || errno == ESRCH else { throw InstanceError.signalFailed }
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeoutSeconds))
        while let currentPID = try owner(descriptor: descriptor) {
            guard currentPID == pid else { throw InstanceError.concurrentStartup }
            guard ContinuousClock.now < deadline else { throw InstanceError.shutdownTimedOut }
            try await Task.sleep(for: .milliseconds(100))
        }
        return true
    }

    private static func writeLock() -> flock {
        var lock = flock()
        lock.l_type = Int16(F_WRLCK)
        lock.l_whence = Int16(SEEK_SET)
        return lock
    }

    private static func owner(descriptor: Int32) throws -> pid_t? {
        var lock = writeLock()
        guard fcntl(descriptor, F_GETLK, &lock) == 0 else { throw InstanceError.lockInspectionFailed }
        return lock.l_type == Int16(F_UNLCK) ? nil : lock.l_pid
    }

    static func reclaimPort(_ port: Int, timeoutSeconds: Int) async throws {
        if checkPortAvailable(port) { return }

        let initialPIDs = listeningProcessIDs(for: port)
        let myPID = getpid()

        for pid in initialPIDs where pid != myPID && pid > 1 {
            _ = kill(pid, SIGTERM)
        }

        let deadline = ContinuousClock.now.advanced(by: .seconds(timeoutSeconds))
        let gracefulDeadline = ContinuousClock.now.advanced(by: .seconds(min(timeoutSeconds, 3)))

        while ContinuousClock.now < deadline {
            if checkPortAvailable(port) { return }

            if ContinuousClock.now >= gracefulDeadline {
                let stubbornPIDs = listeningProcessIDs(for: port)
                for pid in stubbornPIDs where pid != myPID && pid > 1 {
                    _ = kill(pid, SIGKILL)
                }
            }

            try await Task.sleep(for: .milliseconds(100))
        }

        if !checkPortAvailable(port) {
            throw InstanceError.portReclamationFailed
        }
    }

    static func checkPortAvailable(_ port: Int) -> Bool {
        let descriptor = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var value: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bindResult == 0
    }

    static func listeningProcessIDs(for port: Int) -> [pid_t] {
        // Try fuser or lsof if available
        let commands = [
            ("/usr/bin/fuser", ["\(port)/tcp"]),
            ("/bin/fuser", ["\(port)/tcp"]),
            ("/usr/bin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]),
            ("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"])
        ]
        for (exe, args) in commands where FileManager.default.isExecutableFile(atPath: exe) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: exe)
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            if (try? process.run()) != nil {
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    let pids = output.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).compactMap { pid_t($0) }
                    if !pids.isEmpty { return pids }
                }
            }
        }
        return []
    }
}
#endif
