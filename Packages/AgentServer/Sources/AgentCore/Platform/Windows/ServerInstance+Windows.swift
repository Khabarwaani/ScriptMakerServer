#if os(Windows)
import WinSDK
import Foundation

extension ServerInstance: LockPlatformDelegate {
    static func closePlatformDescriptor(_ descriptor: Int32) {
        if descriptor > 0 {
            let handle = HANDLE(bitPattern: Int(descriptor))
            CloseHandle(handle)
        }
    }

    static func openPlatformLock(port: Int) throws -> Int32 {
        let mutexName = "Local\\AgentServer_Port_\(port)"
        let handle = mutexName.withCString(encodedAs: UTF16.self) { wideName in
            CreateMutexW(nil, false, wideName)
        }
        guard let handle else { throw InstanceError.unsafeLockFile }
        return Int32(truncatingIfNeeded: Int(bitPattern: handle))
    }

    static func applyPlatformWriteLock(descriptor: Int32) throws {
        let handle = HANDLE(bitPattern: Int(descriptor))
        let waitResult = WaitForSingleObject(handle, 0)
        guard waitResult == WAIT_OBJECT_0 else {
            throw InstanceError.concurrentStartup
        }
    }

    static func stopPlatformOwner(descriptor: Int32, timeoutSeconds: Int) async throws -> Bool {
        let handle = HANDLE(bitPattern: Int(descriptor))
        let waitResult = WaitForSingleObject(handle, 0)
        if waitResult == WAIT_OBJECT_0 {
            // No previous owner held the mutex
            ReleaseMutex(handle)
            return false
        }
        // Signal graceful shutdown event to running server
        let eventName = "Local\\AgentServer_Shutdown"
        let shutdownEvent = eventName.withCString(encodedAs: UTF16.self) { wideName in
            OpenEventW(DWORD(EVENT_MODIFY_STATE), false, wideName)
        }
        if let shutdownEvent {
            SetEvent(shutdownEvent)
            CloseHandle(shutdownEvent)
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeoutSeconds))
        while ContinuousClock.now < deadline {
            let retryWait = WaitForSingleObject(handle, 100)
            if retryWait == WAIT_OBJECT_0 {
                ReleaseMutex(handle)
                return true
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw InstanceError.shutdownTimedOut
    }

    static func reclaimPort(_ port: Int, timeoutSeconds: Int) async throws {
        // Windows mutex provides single-instance exclusion. Port reclamation via socket reuse.
    }

    static func checkPortAvailable(_ port: Int) -> Bool {
        true
    }
}
#endif
