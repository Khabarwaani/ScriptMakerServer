public actor AppleIntelligenceSession: AgenticSessionProtocol {
    public nonisolated let configuration: Configuration
    private var isBusy = false

    public init?(configuration: Configuration = Configuration()) {
        guard configuration.isValid else { return nil }
        #if canImport(FoundationModels) && (os(macOS) || os(iOS) || os(visionOS))
            guard #available(macOS 26, iOS 26, visionOS 26, *), Self.modelUnavailableReason == nil else { return nil }
            self.configuration = configuration
        #else
            return nil
        #endif
    }

    public func execute(_ operation: any AgenticOperationProtocol) async throws -> AgenticResponse {
        try admit()
        defer { isBusy = false }
        return try await generate(operation, streaming: false, yield: { _ in })
    }

    public func stream(_ operation: any AgenticOperationProtocol) async throws -> (
        snapshots: AsyncThrowingStream<String, any Error>, result: Task<AgenticResponse, any Error>
    ) {
        try admit()
        let (snapshots, continuation) = AsyncThrowingStream<String, any Error>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        let completion = Task {
            defer { isBusy = false }
            do {
                let response = try await generate(operation, streaming: true) { snapshot in
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

    private func admit() throws {
        if Task.isCancelled { throw AgenticSessionError.cancelled }
        guard !isBusy else { throw AgenticSessionError.busy }
        isBusy = true
    }

    private func generate(
        _ operation: any AgenticOperationProtocol, streaming: Bool,
        yield: @escaping @Sendable (String) throws -> Void
    ) async throws -> AgenticResponse {
        #if canImport(FoundationModels) && (os(macOS) || os(iOS) || os(visionOS))
            if #available(macOS 26, iOS 26, visionOS 26, *) {
                return try await perform(operation, streaming: streaming, yield: yield)
            }
        #endif
        throw AgenticSessionError.modelUnavailable(reason: "FoundationModels is unavailable on this platform or OS.")
    }
}
