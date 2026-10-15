#if canImport(FoundationModels) && (os(macOS) || os(iOS) || os(visionOS))
    import Foundation
    internal import FoundationModels

    @available(macOS 26, iOS 26, visionOS 26, *)
    extension AppleIntelligenceSession {
        static var modelUnavailableReason: String? {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return "This device is not eligible for Apple Intelligence."
                case .appleIntelligenceNotEnabled: return "Apple Intelligence is disabled."
                case .modelNotReady: return "The local model is not ready."
                @unknown default: return "The local model is unavailable."
                }
            }
        }

        func perform(
            _ operation: any AgenticOperationProtocol, streaming: Bool,
            yield: @escaping @Sendable (String) throws -> Void
        ) async throws -> (content: Result<String, NSError>, metadata: AgenticExecutionMetadata?) {
            if let reason = Self.modelUnavailableReason { throw AgenticSessionError.modelUnavailable(reason: reason) }
            let input = operation.spec.inputJSON.rawValue
            let instructions = try operation.makeInstructions()
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
            let options = GenerationOptions(
                temperature: configuration.temperature,
                maximumResponseTokens: configuration.maximumResponseTokens)
            let clock = ContinuousClock()
            let start = clock.now
            let response: String
            do {
                try Task.checkCancellation()
                if streaming {
                    let stream = session.streamResponse(to: input, options: options)
                    for try await snapshot in stream {
                        try Task.checkCancellation()
                        try yield(snapshot.content)
                    }
                    try Task.checkCancellation()
                    response = try await stream.collect().content
                    try yield(response)
                } else {
                    response = try await session.respond(to: input, options: options).content
                }
                try Task.checkCancellation()
            } catch {
                throw Self.map(error)
            }
            guard !response.isEmpty else { throw AgenticSessionError.incompleteGeneration }
            let metadata = metadata(duration: start.duration(to: clock.now), session: session)
            let result = try result(from: response)
            if Task.isCancelled { throw AgenticSessionError.cancelled }
            return (content: result, metadata: metadata)
        }

        private func result(from response: String) throws -> Result<String, NSError> {
            let json = try? JSONSerialization.jsonObject(with: Data(response.utf8), options: [.fragmentsAllowed])
            guard let failure = json as? [String: Any], failure["domain"] as? String == "AgentAtom.Operation" else {
                return .success(response)
            }
            guard Set(failure.keys) == ["domain", "code", "reason"],
                failure["code"] as? Int == 422, let reason = failure["reason"] as? String
            else {
                throw AgenticSessionError.invalidResponse
            }
            return .failure(
                NSError(domain: "AgentAtom.Operation", code: 422, userInfo: [NSLocalizedDescriptionKey: reason]))
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

        private static func map(_ error: any Error) -> AgenticSessionError {
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
#endif
