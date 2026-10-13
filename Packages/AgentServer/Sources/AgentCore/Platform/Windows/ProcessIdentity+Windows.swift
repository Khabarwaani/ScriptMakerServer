#if os(Windows)
import Foundation
import WinSDK

// Fail closed until Windows identity and private-manifest ACL verification are
// implemented. Do not terminate processes using unverified numeric PIDs.
extension ProcessIdentity: ProcessIdentityPlatformHook {
    static var currentPID: Int32 { Int32(GetCurrentProcessId()) }
    static var currentUser: UInt32 { UInt32.max }
    static func exists(_ pid: Int32) -> Bool { true }
    static func inspect(_ pid: Int32) -> ProcessIdentity? { nil }
    static func signal(_ identity: ProcessIdentity, _ graceful: Bool) -> Bool { false }
}
#endif
