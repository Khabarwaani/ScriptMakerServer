#if canImport(FoundationModels) && (os(macOS) || os(iOS) || os(visionOS))
    import Foundation
    import Synchronization
    internal import FoundationModels

    @available(macOS 26, iOS 26, visionOS 26, *)
    public final class AppleIntelligenceSession: AgenticSessionProtocol {
        public let configuration: Configuration
        private let state = Mutex(State())

        public var executionMetadata: [AgenticExecutionMetadata] {
            state.withLock { $0.records }
        }

        public init?(configuration: Configuration = Configuration()) {
            self.configuration = configuration
            guard case .available = SystemLanguageModel.default.availability else { return nil }
        }

        public func respond(
            to input: String, instructions: String, for operation: ObjectIdentifier
        ) async -> Result<String, AgenticError> {
            do {
                let run = try begin(instructions: instructions, for: operation)
                defer { finish(run) }
                let response = try await run.model.respond(to: input, options: run.options)
                return try result(response.content)
            } catch {
                return .failure(map(error))
            }
        }

        public func stream(
            to input: String, instructions: String, for operation: ObjectIdentifier,
            yield: @Sendable (String) async throws -> Void
        ) async -> Result<String, AgenticError> {
            do {
                let run = try begin(instructions: instructions, for: operation)
                defer { finish(run) }
                let stream = run.model.streamResponse(to: input, options: run.options)
                for try await snapshot in stream {
                    try Task.checkCancellation()
                    try await yield(snapshot.content)
                }
                let response = try await stream.collect()
                return try result(response.content)
            } catch {
                return .failure(map(error))
            }
        }

        public struct Configuration: Sendable {
            public let metadata: AgenticExecutionMetadata.Fields
            public let temperature: Double

            public init(metadata: AgenticExecutionMetadata.Fields = [], temperature: Double = 1) {
                self.metadata = metadata
                self.temperature = temperature.isNaN ? 1 : min(max(temperature, 0), 1)
            }
        }

        private struct State: Sendable {
            var isBusy = false
            var records: [AgenticExecutionMetadata] = []
        }

        private struct Run {
            let id: UUID
            let operation: ObjectIdentifier
            let model: LanguageModelSession
            let options: GenerationOptions
            let started: ContinuousClock.Instant
        }

        private func begin(instructions: String, for operation: ObjectIdentifier) throws(AgenticError) -> Run {
            guard !Task.isCancelled else { throw .cancelled }
            let admitted = state.withLock { storage in
                guard !storage.isBusy else { return false }
                storage.isBusy = true
                return true
            }
            guard admitted else { throw .busy }
            return Run(
                id: UUID(), operation: operation,
                model: LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions),
                options: GenerationOptions(temperature: configuration.temperature),
                started: ContinuousClock().now)
        }

        private func result(_ text: String) throws(AgenticError) -> Result<String, AgenticError> {
            guard !Task.isCancelled else { throw .cancelled }
            guard !text.isEmpty else { throw .incompleteGeneration }
            return .success(text)
        }

        private func finish(_ run: Run) {
            let fields = configuration.metadata
            var promptTokens: Int?
            var completionTokens: Int?
            #if compiler(>=6.4)
                if #available(macOS 27, iOS 27, visionOS 27, *), fields.contains(.tokenUsage) {
                    promptTokens = run.model.usage.input.totalTokenCount
                    completionTokens = run.model.usage.output.totalTokenCount
                }
            #endif
            let record = AgenticExecutionMetadata(
                operationID: run.operation, executionID: run.id,
                modelIdentifier: fields.contains(.modelIdentifier) ? "SystemLanguageModel.default" : nil,
                duration: fields.contains(.duration) ? run.started.duration(to: ContinuousClock().now) : nil,
                promptTokens: promptTokens, completionTokens: completionTokens)
            state.withLock { storage in
                storage.records.append(record)
                storage.isBusy = false
            }
        }

        private func map(_ error: any Error) -> AgenticError {
            if error is CancellationError || Task.isCancelled { return .cancelled }
            if let error = error as? AgenticError { return error }
            #if compiler(>=6.4)
                if #available(macOS 27, iOS 27, visionOS 27, *) {
                    if let error = error as? LanguageModelError {
                        switch error {
                        case .contextSizeExceeded: return .contextLengthExceeded
                        case .rateLimited: return .rateLimited
                        case .guardrailViolation, .refusal: return .refusal
                        default: return .executionFailed
                        }
                    }
                    if error is SystemLanguageModel.Error {
                        return .modelUnavailable(reason: "The local model assets are unavailable.")
                    }
                    if let error = error as? LanguageModelSession.Error, error == .concurrentRequests { return .busy }
                }
            #endif
            if let error = error as? LanguageModelSession.GenerationError {
                switch error {
                case .exceededContextWindowSize: return .contextLengthExceeded
                case .assetsUnavailable: return .modelUnavailable(reason: "The local model assets are unavailable.")
                case .guardrailViolation, .refusal: return .refusal
                case .decodingFailure: return .incompleteGeneration
                case .rateLimited: return .rateLimited
                case .concurrentRequests: return .busy
                default: return .executionFailed
                }
            }
            return .executionFailed
        }
    }
#endif
