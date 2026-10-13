#if os(macOS)
import Darwin
import Foundation

extension ProcessIdentity: ProcessIdentityPlatformHook {
    static var currentPID: Int32 { getpid() }
    static var currentUser: UInt32 { getuid() }
    static func exists(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno != ESRCH }
    static func inspect(_ pid: Int32) -> ProcessIdentity? {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size else { return nil }
        // Zombies have no executable and are already terminated.
        var path = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        let executable = path.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        return ProcessIdentity(pid: pid, parentPID: Int32(info.pbi_ppid), group: getpgid(pid), user: info.pbi_uid,
                               birth: "\(info.pbi_start_tvsec):\(info.pbi_start_tvusec)", executable: executable)
    }
    static func signal(_ identity: ProcessIdentity, _ graceful: Bool) -> Bool {
        guard identity.pid > 1, identity.user == currentUser, identity.matches(inspect(identity.pid)) else { return false }
        let target = identity.group == identity.pid && getpgid(identity.pid) == identity.pid ? -identity.pid : identity.pid
        return kill(target, graceful ? SIGTERM : SIGKILL) == 0 || errno == ESRCH
    }
}
#endif
