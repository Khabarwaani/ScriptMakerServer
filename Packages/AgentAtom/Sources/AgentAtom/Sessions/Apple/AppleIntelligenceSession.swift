#if canImport(FoundationModels) && (os(macOS) || os(iOS) || os(visionOS))
    import Foundation
    internal import FoundationModels

    @available(macOS 26, iOS 26, visionOS 26, *)
    public actor AppleIntelligenceSession: AgenticSessionProtocol {
        public nonisolated let configuration: Configuration
        public private(set) var executionMetadata: [AgenticExecutionMetadata] = []
        private var isBusy = false

        public init?(configuration: Configuration = Configuration()) {
            self.configuration = configuration
            guard case .available = SystemLanguageModel.default.availability else { return nil }
        }

        public func execute<Operation: AgenticOperationProtocol>(_ operation: Operation) async -> Result<String, NSError> {
            do {
                try admit()
                defer { isBusy = false }
                return try await perform(operation)
            } catch {
                let failure = map(error)
                return .failure(failure as NSError)
            }
        }

        public func stream<Operation: AgenticOperationProtocol>(
            _ operation: Operation
        ) async -> AsyncStream<Result<String, NSError>> {
            let (results, continuation) = AsyncStream<Result<String, NSError>>.makeStream(
                bufferingPolicy: .bufferingNewest(1))
            do {
                try admit()
            } catch {
                let failure = map(error)
                continuation.yield(.failure(failure as NSError))
                continuation.finish()
                return results
            }
            let producer = Task {
                defer {
                    isBusy = false
                    continuation.finish()
                }
                do {
                    let response = try await performStream(operation) { snapshot in
                        if case .terminated = continuation.yield(.success(snapshot)) {
                            throw AgenticSessionError.cancelled
                        }
                    }
                    continuation.yield(response)
                } catch {
                    let failure = map(error)
                    continuation.yield(.failure(failure as NSError))
                }
            }
            continuation.onTermination = { termination in
                if case .cancelled = termination { producer.cancel() }
            }
            return results
        }

        public struct Configuration: Sendable {
            public let metadata: Set<AgenticExecutionMetadataField>
            @Clamped(0...1, default: 1) private var temperatureValue: Double
            public var temperature: Double { temperatureValue }

            public init(metadata: Set<AgenticExecutionMetadataField> = [], temperature: Double = 1) {
                self.metadata = metadata
                self.temperatureValue = temperature
            }
        }

        private func admit() throws {
            if Task.isCancelled { throw AgenticSessionError.cancelled }
            guard !isBusy else { throw AgenticSessionError.busy }
            isBusy = true
        }

        private func perform<Operation: AgenticOperationProtocol>(
            _ operation: Operation
        ) async throws -> Result<String, NSError> {
            let input = operation.spec.inputJSON.rawValue
            let instructions: String
            instructions = try operation.makeInstructions()
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
            let options = GenerationOptions(temperature: configuration.temperature)
            let clock = ContinuousClock()
            let start = clock.now
            let response: String
            try Task.checkCancellation()
            response = try await session.respond(to: input, options: options).content
            try Task.checkCancellation()
            guard !response.isEmpty else { throw AgenticSessionError.incompleteGeneration }
            let responseMetadata = metadata(duration: start.duration(to: clock.now), session: session)
            let result = try result(from: response)
            try Task.checkCancellation()
            if let responseMetadata { executionMetadata.append(responseMetadata) }
            return result
        }

        private func performStream<Operation: AgenticOperationProtocol>(
            _ operation: Operation, yield: @Sendable (String) async throws -> Void
        ) async throws -> Result<String, NSError> {
            let input = operation.spec.inputJSON.rawValue
            let instructions = try operation.makeInstructions()
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
            let options = GenerationOptions(temperature: configuration.temperature)
            let clock = ContinuousClock()
            let start = clock.now
            let response: String
            try Task.checkCancellation()
            let stream = session.streamResponse(to: input, options: options)
            for try await snapshot in stream {
                try Task.checkCancellation()
                try await yield(snapshot.content)
            }
            try Task.checkCancellation()
            response = try await stream.collect().content
            try Task.checkCancellation()
            guard !response.isEmpty else { throw AgenticSessionError.incompleteGeneration }
            let responseMetadata = metadata(duration: start.duration(to: clock.now), session: session)
            let result = try result(from: response)
            try Task.checkCancellation()
            if let responseMetadata { executionMetadata.append(responseMetadata) }
            return result
        }

        private func result(from response: String) throws -> Result<String, NSError> {
            guard let data = response.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["domain"] as? String == "AgentAtom.Operation" else {
                return .success(response)
            }
            guard let failure = try? JSONDecoder().decode(OperationFailure.self, from: data), failure.code == 422 else {
                throw AgenticSessionError.invalidResponse
            }
            return .failure(
                NSError(domain: failure.domain, code: failure.code, userInfo: [NSLocalizedDescriptionKey: failure.reason]))
        }

        private func metadata(duration: Duration, session: LanguageModelSession) -> AgenticExecutionMetadata? {
            let fields = configuration.metadata
            guard !fields.isEmpty else { return nil }
            var promptTokens: Int?
            var completionTokens: Int?
            #if compiler(>=6.4)
                if #available(macOS 27, iOS 27, visionOS 27, *), fields.contains(.tokenUsage) {
                    promptTokens = session.usage.input.totalTokenCount
                    completionTokens = session.usage.output.totalTokenCount
                }
            #endif
            return AgenticExecutionMetadata(
                modelIdentifier: fields.contains(.modelIdentifier) ? "SystemLanguageModel.default" : nil,
                duration: fields.contains(.duration) ? duration : nil,
                promptTokens: promptTokens, completionTokens: completionTokens
            )
        }

        private func map(_ error: any Error) -> AgenticSessionError {
            if error is CancellationError || Task.isCancelled { return .cancelled }
            if let error = error as? AgenticSessionError { return error }
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
