#if os(Linux)
import Glibc
import Foundation

extension ProcessRunner: ProcessRunnerPlatformHook {
    func configurePlatformPipe(_ handle: FileHandle) {
        _ = signal(SIGPIPE, SIG_IGN)
    }

    func platformResidentMemory(pid: Int32) -> UInt64 {
        guard let statm = try? String(contentsOfFile: "/proc/\(pid)/statm", encoding: .utf8) else { return 0 }
        let parts = statm.split(separator: " ")
        guard parts.count >= 2, let residentPages = UInt64(parts[1]) else { return 0 }
        let pageSize = UInt64(sysconf(Int32(_SC_PAGESIZE)))
        return residentPages * (pageSize > 0 ? pageSize : 4096)
    }

    func platformSignal(process: Process, graceful: Bool) {
        _ = kill(process.processIdentifier, graceful ? SIGTERM : SIGKILL)
    }

    static var platformPathSeparator: Character { ":" }
    static var platformStandardPaths: [String] {
        ["/usr/local/bin", "/usr/bin", "/bin", "/snap/bin"]
    }
    static var platformExecutableExtensions: [String] { [""] }
}
#endif
