import Darwin
import Foundation

public struct SystemResources: Codable, Sendable {
    public let physical_memory_bytes: UInt64
    public let available_memory_bytes: UInt64?
    public let load_average: Double?
    public let cpu_count: Int

    public init(
        physical_memory_bytes: UInt64, available_memory_bytes: UInt64?, load_average: Double?, cpu_count: Int
    ) {
        self.physical_memory_bytes = physical_memory_bytes
        self.available_memory_bytes = available_memory_bytes
        self.load_average = load_average
        self.cpu_count = cpu_count
    }

    public static func sample() -> SystemResources {
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let physical = ProcessInfo.processInfo.physicalMemory
        let available: UInt64?
        if result == KERN_SUCCESS {
            let pages =
                UInt64(statistics.free_count) + UInt64(statistics.inactive_count)
                + UInt64(statistics.purgeable_count)
            available = min(physical, pages * UInt64(getpagesize()))
        } else {
            available = nil
        }
        var load = [Double](repeating: 0, count: 1)
        let hasLoad = getloadavg(&load, 1) == 1
        return SystemResources(
            physical_memory_bytes: physical, available_memory_bytes: available,
            load_average: hasLoad ? load[0] : nil, cpu_count: ProcessInfo.processInfo.activeProcessorCount)
    }
}
