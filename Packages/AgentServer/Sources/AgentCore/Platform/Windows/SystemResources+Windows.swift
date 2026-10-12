#if os(Windows)
import WinSDK
import Foundation

extension SystemResources: ResourcePlatformDelegate {
    static func samplePlatform() -> SystemResources {
        let physical = ProcessInfo.processInfo.physicalMemory
        var memStatus = MEMORYSTATUSEX()
        memStatus.dwLength = DWORD(MemoryLayout<MEMORYSTATUSEX>.size)
        let available: UInt64? = GlobalMemoryStatusEx(&memStatus) ? UInt64(memStatus.ullAvailPhys) : nil
        return SystemResources(
            physical_memory_bytes: physical, available_memory_bytes: available,
            load_average: nil, cpu_count: ProcessInfo.processInfo.activeProcessorCount)
    }
}
#endif
