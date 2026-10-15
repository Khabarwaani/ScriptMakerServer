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

        public func generate(
            input: String, instructions: String, operationID: UUID
        ) async -> Result<String, AgenticError> {
            await perform(instructions: instructions, operationID: operationID) { session, options in
                try await session.respond(to: input, options: options).content
            }
        }

        public func stream(
            input: String, instructions: String, operationID: UUID,
            yield: @Sendable (String) async throws -> Void
        ) async -> Result<String, AgenticError> {
            await perform(instructions: instructions, operationID: operationID) { session, options in
                let stream = session.streamResponse(to: input, options: options)
                for try await snapshot in stream {
                    try Task.checkCancellation()
                    try await yield(snapshot.content)
                }
                try Task.checkCancellation()
                return try await stream.collect().content
            }
        }

        public struct Configuration: Sendable {
            public let metadata: AgenticExecutionMetadata.Fields
            @Clamped(0...1, default: 1) private var temperatureValue: Double
            public var temperature: Double { temperatureValue }

            public init(metadata: AgenticExecutionMetadata.Fields = [], temperature: Double = 1) {
                self.metadata = metadata
                self.temperatureValue = temperature
            }
        }

        private struct State: Sendable {
            var isBusy = false
            var records: [AgenticExecutionMetadata] = []
        }

        private func admit() -> AgenticError? {
            if Task.isCancelled { return .cancelled }
            return state.withLock { storage in
                guard !storage.isBusy else { return .busy }
                storage.isBusy = true
                return nil
            }
        }

        private func perform(
            instructions: String, operationID: UUID,
            generation: @Sendable (LanguageModelSession, GenerationOptions) async throws -> String
        ) async -> Result<String, AgenticError> {
            if let failure = admit() { return .failure(failure) }
            let executionID = UUID()
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
            let clock = ContinuousClock()
            let start = clock.now
            defer {
                let record = metadata(
                    operationID: operationID, executionID: executionID,
                    duration: start.duration(to: clock.now), session: session)
                state.withLock { storage in
                    storage.records.append(record)
                    storage.isBusy = false
                }
            }
            do {
                try Task.checkCancellation()
                let response = try await generation(session, GenerationOptions(temperature: configuration.temperature))
                try Task.checkCancellation()
                guard !response.isEmpty else { throw AgenticError.incompleteGeneration }
                return .success(response)
            } catch {
                return .failure(map(error))
            }
        }

        private func metadata(
            operationID: UUID, executionID: UUID, duration: Duration, session: LanguageModelSession
        ) -> AgenticExecutionMetadata {
            let fields = configuration.metadata
            var promptTokens: Int?
            var completionTokens: Int?
            #if compiler(>=6.4)
                if #available(macOS 27, iOS 27, visionOS 27, *), fields.contains(.tokenUsage) {
                    promptTokens = session.usage.input.totalTokenCount
                    completionTokens = session.usage.output.totalTokenCount
                }
            #endif
            return AgenticExecutionMetadata(
                operationID: operationID, executionID: executionID,
                modelIdentifier: fields.contains(.modelIdentifier) ? "SystemLanguageModel.default" : nil,
                duration: fields.contains(.duration) ? duration : nil,
                promptTokens: promptTokens, completionTokens: completionTokens
            )
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

    @propertyWrapper
    private struct Clamped<Value: BinaryFloatingPoint & Sendable>: Sendable {
        private let range: ClosedRange<Value>
        private let fallback: Value
        private var value: Value

        var wrappedValue: Value {
            get { value }
            set { value = newValue.isNaN ? fallback : min(max(newValue, range.lowerBound), range.upperBound) }
        }

        init(_ range: ClosedRange<Value>, default fallback: Value) {
            self.range = range
            self.fallback = min(max(fallback, range.lowerBound), range.upperBound)
            self.value = self.fallback
        }
    }
#endif
