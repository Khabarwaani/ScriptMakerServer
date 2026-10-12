#if os(macOS)
import Darwin
import Foundation

extension ProcessRunner: ProcessRunnerPlatformHook {
    func configurePlatformPipe(_ handle: FileHandle) {
        _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
    }

    func platformResidentMemory(pid: Int32) -> UInt64 {
        var info = proc_taskinfo()
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size)) > 0
        else { return 0 }
        return info.pti_resident_size
    }

    func platformSignal(process: Process, graceful: Bool) {
        let pid = process.processIdentifier
        let sig = graceful ? SIGTERM : SIGKILL
        if getpgid(pid) == pid {
            _ = kill(-pid, sig)
        } else {
            _ = kill(pid, sig)
        }
    }

    static var platformPathSeparator: Character { ":" }
    static var platformStandardPaths: [String] {
        ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
    }
    static var platformExecutableExtensions: [String] { [""] }
}
#endif
