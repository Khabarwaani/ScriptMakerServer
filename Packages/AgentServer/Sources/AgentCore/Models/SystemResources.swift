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
        samplePlatform()
    }
}
