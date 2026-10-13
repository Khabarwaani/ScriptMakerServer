import Foundation
import NIOCore
import NIOPosix
import Testing

@testable import AgentCore

@Test func testPortsSkipOccupiedCandidatesAndRetryStartupCollisions() async throws {
    let configuration = try TestingPortConfiguration()
    var checked: [Int] = []
    var started: [Int] = []
    let selected = try await TestingPortAllocator.attempt(
        configuration: configuration, candidates: [9001, 9002, 9003],
        isAvailable: { port in
            checked.append(port)
            return port != 9001
        }, operation: { port in
            started.append(port)
            if port == 9002 { throw TestingPortAllocator.AllocationError.portInUse }
            return port
        })
    #expect(selected == 9003)
    #expect(checked == [9001, 9002, 9003])
    #expect(started == [9002, 9003])
}

@Test func testPortsStopAfterThirtyDistinctAttempts() async throws {
    var checked: [Int] = []
    do {
        _ = try await TestingPortAllocator.attempt(
            configuration: TestingPortConfiguration(), candidates: [9000, 9000, 8080, 8081] + Array(9001...9040),
            isAvailable: { checked.append($0); return false }, operation: { $0 })
        Issue.record("Expected port allocation to fail.")
    } catch TestingPortAllocator.AllocationError.exhausted(let range, let attempts) {
        #expect(range == 9000...9999)
        #expect(attempts == 30)
        #expect(checked == Array(9000...9029))
    }
}

@Test func testPortsExhaustSmallConfiguredRangeWithoutRepeating() async throws {
    let configuration = try TestingPortConfiguration(min: 9100, max: 9101)
    do {
        _ = try await TestingPortAllocator.attempt(
            configuration: configuration, candidates: [9100, 9101, 9100],
            isAvailable: { _ in false }, operation: { $0 })
        Issue.record("Expected range exhaustion.")
    } catch TestingPortAllocator.AllocationError.exhausted(let range, let attempts) {
        #expect(range == 9100...9101)
        #expect(attempts == 2)
    }
}

private enum UnrelatedStartupError: Error { case failed }

@Test func testPortsDoNotRetryUnrelatedStartupErrors() async throws {
    var started: [Int] = []
    await #expect(throws: UnrelatedStartupError.self) {
        _ = try await TestingPortAllocator.attempt(
            configuration: TestingPortConfiguration(), candidates: [9200, 9201],
            isAvailable: { _ in true }, operation: { port -> Int in
                started.append(port)
                throw UnrelatedStartupError.failed
            })
    }
    #expect(started == [9200])
}

@Test func testPortChecksPropagateProbeErrors() async throws {
    await #expect(throws: UnrelatedStartupError.self) {
        _ = try await TestingPortAllocator.attempt(
            configuration: TestingPortConfiguration(), candidates: [9300],
            isAvailable: { _ in throw UnrelatedStartupError.failed }, operation: { $0 })
    }
}

@Test func realPortProbeDetectsAnOccupiedTestListener() async throws {
    let listener = try await acquireTestListener()
    defer { listener.close(promise: nil) }
    let port = try #require(listener.localAddress?.port)
    #expect((9000...9999).contains(port))
    #expect(try await !TestingPortAllocator.isAvailable(port: port))
}

@Test func concurrentTestListenersUseDistinctPorts() async throws {
    async let first = acquireTestListener()
    async let second = acquireTestListener()
    async let third = acquireTestListener()
    let listeners = try await [first, second, third]
    defer { for listener in listeners { listener.close(promise: nil) } }
    let ports = listeners.compactMap { $0.localAddress?.port }
    #expect(ports.count == 3)
    #expect(Set(ports).count == 3)
    #expect(ports.allSatisfy { (9000...9999).contains($0) })
}

private func acquireTestListener() async throws -> any Channel {
    let configuration = try ServerConfiguration(environment: ["AGENT_SERVER_ENV": "testing"])
    return try await TestingPortAllocator.withAvailablePort(configuration: configuration.testingPorts) { port in
        do {
            return try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                .bind(host: configuration.host, port: port).get()
        } catch {
            if TestingPortAllocator.isAddressInUse(error) { throw TestingPortAllocator.AllocationError.portInUse }
            throw error
        }
    }
}
