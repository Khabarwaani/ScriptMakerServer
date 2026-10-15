import Foundation

/// Independent local-model session. Create separate instances for concurrency.
public actor AppleIntelligenceSession: AgenticSessionProtocol {
    public struct Configuration: Sendable {
        public let instructions: String?
        public let supportedOutputTypes: Set<AgenticOutputKind>
        public let metadata: Set<AgenticMetadataField>
        public let temperature: Double?
        public let maximumResponseTokens: Int?

        public init(
            instructions: String? = nil,
            supportedOutputTypes: Set<AgenticOutputKind> = [.text, .json],
            metadata: Set<AgenticMetadataField> = [],
            temperature: Double? = nil, maximumResponseTokens: Int? = nil
        ) {
            self.instructions = instructions
            self.supportedOutputTypes = supportedOutputTypes
            self.metadata = metadata
            self.temperature = temperature
            self.maximumResponseTokens = maximumResponseTokens
        }

        func validate() throws {
            guard !supportedOutputTypes.isEmpty,
                supportedOutputTypes.isSubset(of: [.text, .json])
            else {
                throw AgenticSessionError.invalidConfiguration(
                    reason: "Apple local LLM supports text and JSON output only.")
            }
            if let temperature, !temperature.isFinite || !(0...2).contains(temperature) {
                throw AgenticSessionError.invalidConfiguration(
                    reason: "Temperature must be finite and between zero and two.")
            }
            if let maximumResponseTokens, maximumResponseTokens <= 0 {
                throw AgenticSessionError.invalidConfiguration(reason: "Maximum response tokens must be positive.")
            }
        }
    }

    public nonisolated let configuration: Configuration
    private let backend: any AppleGenerationBackend
    private var isBusy = false

    public init(configuration: Configuration = Configuration()) throws {
        try configuration.validate()
        self.configuration = configuration
        #if canImport(FoundationModels) && (os(macOS) || os(iOS) || os(visionOS))
            if #available(macOS 26, iOS 26, visionOS 26, *) {
                self.backend = try FoundationModelsBackend(configuration: configuration)
            } else {
                throw AgenticSessionError.modelUnavailable(reason: "Requires macOS, iOS, or visionOS 26 or later.")
            }
        #else
            throw AgenticSessionError.modelUnavailable(
                reason: "FoundationModels is unavailable on this platform or toolchain.")
        #endif
    }

    /// Internal injection point for the separate lifecycle-testing task.
    init(configuration: Configuration, backend: any AppleGenerationBackend) throws {
        try configuration.validate()
        self.configuration = configuration
        self.backend = backend
    }

    public func respond(to request: AgenticRequest) async throws -> AgenticResponse<AgenticContent> {
        try admit(request)
        defer { isBusy = false }
        return try await generate(request, streaming: false, yield: { _ in })
    }

    public func streamResponse(to request: AgenticRequest) async throws -> AgenticStream<AgenticContent> {
        try admit(request)
        let pair = AsyncThrowingStream<AgenticContent, any Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let completion = Task {
            defer { isBusy = false }
            do {
                let response = try await generate(request, streaming: true) { content in
                    if case .terminated = pair.continuation.yield(content) {
                        throw AgenticSessionError.cancelled
                    }
                }
                try Self.checkCancellation()
                pair.continuation.yield(response.content)
                pair.continuation.finish()
                return response
            } catch {
                pair.continuation.finish(throwing: error)
                throw error
            }
        }
        pair.continuation.onTermination = { termination in
            if case .cancelled = termination { completion.cancel() }
        }
        return AgenticStream(snapshots: pair.stream, completion: completion)
    }

    private func admit(_ request: AgenticRequest) throws {
        try Self.checkCancellation()
        guard !isBusy else { throw AgenticSessionError.busy }
        guard configuration.supportedOutputTypes.contains(request.output.kind) else {
            throw AgenticSessionError.unsupportedOutput(request.output.kind)
        }
        if case .image = request.input { throw AgenticSessionError.unsupportedInput }
        isBusy = true
    }

    private func generate(
        _ request: AgenticRequest, streaming: Bool,
        yield: @escaping @Sendable (AgenticContent) throws -> Void
    ) async throws -> AgenticResponse<AgenticContent> {
        do {
            try Self.checkCancellation()
            let response = try await backend.generate(
                request: request,
                instructions: SessionRequestAssembler.instructions(base: configuration.instructions, request: request),
                streaming: streaming, yield: yield
            )
            try Self.checkCancellation()
            return response
        } catch is CancellationError {
            throw AgenticSessionError.cancelled
        } catch {
            if Task.isCancelled { throw AgenticSessionError.cancelled }
            throw error
        }
    }

    private static func checkCancellation() throws {
        if Task.isCancelled { throw AgenticSessionError.cancelled }
    }
}

protocol AppleGenerationBackend: Sendable {
    func generate(
        request: AgenticRequest, instructions: String, streaming: Bool,
        yield: @escaping @Sendable (AgenticContent) throws -> Void
    ) async throws -> AgenticResponse<AgenticContent>
}
