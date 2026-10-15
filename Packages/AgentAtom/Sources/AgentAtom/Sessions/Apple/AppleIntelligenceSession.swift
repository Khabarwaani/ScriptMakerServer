import Foundation

@available(macOS 26, iOS 26, visionOS 26, *)
public actor AppleIntelligenceSession: AgenticSessionProtocol {
    public typealias SessionError = AgenticSessionError
    public nonisolated let configuration: Configuration
    private var isBusy = false

    public init?(configuration: Configuration = Configuration()) {
        #if canImport(FoundationModels) && (os(macOS) || os(iOS) || os(visionOS))
            guard Self.modelUnavailableReason == nil else { return nil }
            self.configuration = configuration
        #else
            return nil
        #endif
    }

    public func execute(_ operation: any AgenticOperationProtocol) async throws(AgenticSessionError) -> (
        content: Result<String, NSError>, metadata: AgenticExecutionMetadata?
    ) {
        try admit()
        defer { isBusy = false }
        return try await generate(operation, streaming: false, yield: { _ in })
    }

    public func stream(_ operation: any AgenticOperationProtocol) async throws(AgenticSessionError) -> (
        snapshots: AsyncThrowingStream<String, any Error>,
        result: Task<(content: Result<String, NSError>, metadata: AgenticExecutionMetadata?), any Error>
    ) {
        try admit()
        let (snapshots, continuation) = AsyncThrowingStream<String, any Error>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        let completion = Task {
            defer { isBusy = false }
            do {
                let response = try await generate(operation, streaming: true) { snapshot async throws(AgenticSessionError) in
                    if case .terminated = continuation.yield(snapshot) {
                        throw AgenticSessionError.cancelled
                    }
                }
                continuation.finish()
                return response
            } catch {
                continuation.finish(throwing: error)
                throw error
            }
        }
        continuation.onTermination = { termination in
            if case .cancelled = termination { completion.cancel() }
        }
        return (snapshots: snapshots, result: completion)
    }

    private func admit() throws(AgenticSessionError) {
        if Task.isCancelled { throw AgenticSessionError.cancelled }
        guard !isBusy else { throw AgenticSessionError.busy }
        isBusy = true
    }

    private func generate(
        _ operation: any AgenticOperationProtocol, streaming: Bool,
        yield: @escaping @Sendable (String) async throws(AgenticSessionError) -> Void
    ) async throws(AgenticSessionError) -> (content: Result<String, NSError>, metadata: AgenticExecutionMetadata?) {
        #if canImport(FoundationModels) && (os(macOS) || os(iOS) || os(visionOS))
            return try await perform(operation, streaming: streaming, yield: yield)
        #else
            throw AgenticSessionError.modelUnavailable(reason: "FoundationModels is unavailable on this platform or OS.")
        #endif
    }
}
