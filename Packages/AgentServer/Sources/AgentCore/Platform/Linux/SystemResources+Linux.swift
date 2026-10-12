#if os(Linux)
import Glibc
import Foundation

extension SystemResources: ResourcePlatformDelegate {
    static func samplePlatform() -> SystemResources {
        let physical = ProcessInfo.processInfo.physicalMemory
        var available: UInt64? = nil
        if let meminfo = try? String(contentsOfFile: "/proc/meminfo", encoding: .utf8) {
            for line in meminfo.split(separator: "\n") {
                if line.hasPrefix("MemAvailable:") {
                    let parts = line.split(whereSeparator: { $0.isWhitespace })
                    if parts.count >= 2, let kb = UInt64(parts[1]) {
                        available = kb * 1024
                        break
                    }
                }
            }
        }
        var load = [Double](repeating: 0, count: 1)
        let hasLoad = getloadavg(&load, 1) == 1
        return SystemResources(
            physical_memory_bytes: physical, available_memory_bytes: available,
            load_average: hasLoad ? load[0] : nil, cpu_count: ProcessInfo.processInfo.activeProcessorCount)
    }
}
#endif
