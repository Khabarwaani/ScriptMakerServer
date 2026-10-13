#if os(Windows)
import WinSDK
import Foundation

extension ProcessRunner: ProcessRunnerPlatformHook {
    func configurePlatformPipe(_ handle: FileHandle) {
        // Safe no-op on Windows
    }

    func platformResidentMemory(pid: Int32) -> UInt64 {
        var pmc = PROCESS_MEMORY_COUNTERS()
        guard let handle = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, DWORD(pid)) else {
            return 0
        }
        defer { CloseHandle(handle) }
        guard GetProcessMemoryInfo(handle, &pmc, DWORD(MemoryLayout<PROCESS_MEMORY_COUNTERS>.size)) else {
            return 0
        }
        return UInt64(pmc.WorkingSetSize)
    }

    func platformSignal(process: Process, graceful: Bool) {
        if graceful {
            process.terminate()
        } else {
            let pid = process.processIdentifier
            if let handle = OpenProcess(DWORD(PROCESS_TERMINATE), false, DWORD(pid)) {
                defer { CloseHandle(handle) }
                _ = TerminateProcess(handle, 1)
            } else {
                process.terminate()
            }
        }
    }

    static var platformPathSeparator: Character { ";" }
    static var platformStandardPaths: [String] {
        ["C:\\Windows\\System32", "C:\\Windows"]
    }
    static var platformExecutableExtensions: [String] {
        ["", ".exe", ".cmd", ".bat"]
    }
}
#endif
