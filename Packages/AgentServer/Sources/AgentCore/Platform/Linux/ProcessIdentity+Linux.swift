#if os(Linux)
import Glibc
import Foundation

extension ProcessIdentity: ProcessIdentityPlatformHook {
    static var currentPID: Int32 { getpid() }
    static var currentUser: UInt32 { getuid() }
    static func exists(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno != ESRCH }
    static func inspect(_ pid: Int32) -> ProcessIdentity? {
        let root = "/proc/\(pid)"
        guard let stat = try? String(contentsOfFile: root + "/stat", encoding: .utf8),
              let end = stat.lastIndex(of: ")"),
              let executable = try? FileManager.default.destinationOfSymbolicLink(atPath: root + "/exe"),
              let boot = try? String(contentsOfFile: "/proc/sys/kernel/random/boot_id", encoding: .utf8),
              let namespace = try? FileManager.default.destinationOfSymbolicLink(atPath: root + "/ns/pid"),
              let attrs = try? FileManager.default.attributesOfItem(atPath: root),
              let user = (attrs[.ownerAccountID] as? NSNumber)?.uint32Value else { return nil }
        let parts = stat[stat.index(after: end)...].split(separator: " ")
        guard parts.count > 19, parts[0] != "Z", let parent = Int32(parts[1]), let group = Int32(parts[2]) else { return nil }
        return ProcessIdentity(pid: pid, parentPID: parent, group: group, user: user,
                               birth: boot.trimmingCharacters(in: .whitespacesAndNewlines) + ":" + namespace + ":" + String(parts[19]), executable: executable)
    }
    static func signal(_ identity: ProcessIdentity, _ graceful: Bool) -> Bool {
        guard identity.pid > 1, identity.user == currentUser, identity.matches(inspect(identity.pid)) else { return false }
        let target = identity.group == identity.pid && getpgid(identity.pid) == identity.pid ? -identity.pid : identity.pid
        return kill(target, graceful ? SIGTERM : SIGKILL) == 0 || errno == ESRCH
    }
}
#endif
