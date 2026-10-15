#if os(macOS) || os(Linux)
@testable import AgentAtom
import Foundation
import Testing

struct FailureTests {
    @Test
    func testFailuresTerminateInIsolatedProcesses() throws {
        #if os(macOS)
        let executable = Bundle(for: TestBundleAnchor.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("FailureProbe")
        #else
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            .appendingPathComponent("FailureProbe")
        #endif
        try #require(FileManager.default.isExecutableFile(atPath: executable.path))
        for scenario in ["valid", "literal", "input", "schema"] {
            let process = Process()
            process.executableURL = executable
            process.arguments = [scenario]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            if scenario == "valid" {
                #expect(process.terminationReason == .exit)
                #expect(process.terminationStatus == 0)
            } else {
                #expect(process.terminationReason == .uncaughtSignal, "\(scenario)")
            }
        }
    }
}

#if os(macOS)
private final class TestBundleAnchor: NSObject {}
#endif
#endif
