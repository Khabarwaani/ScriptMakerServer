#if canImport(FoundationModels) && (os(macOS) || os(iOS) || os(visionOS))
    import Foundation
    internal import FoundationModels

    @available(macOS 26, iOS 26, visionOS 26, *)
    struct FoundationModelsBackend: AppleGenerationBackend {
        let configuration: AppleIntelligenceSession.Configuration

        init(configuration: AppleIntelligenceSession.Configuration) throws {
            try Self.checkAvailability()
            self.configuration = configuration
        }

        func generate(
            request: AgenticRequest, instructions: String, streaming: Bool,
            yield: @escaping @Sendable (AgenticContent) throws -> Void
        ) async throws -> AgenticResponse<AgenticContent> {
            try Self.checkAvailability()
            let prompt: String
            switch request.input {
            case .text(let text): prompt = text
            case .json(let json): prompt = json.rawValue
            case .image: throw AgenticSessionError.unsupportedInput
            }
            let schema: GenerationSchema?
            switch request.output {
            case .text: schema = nil
            case .json(let value): schema = try AppleSchemaTranslator.translate(value)
            case .image: throw AgenticSessionError.unsupportedOutput(.image)
            }
            // Fresh provider conversation per request; no shared history or model fallback.
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
            let options = GenerationOptions(
                temperature: configuration.temperature,
                maximumResponseTokens: configuration.maximumResponseTokens)
            let clock = ContinuousClock()
            let start = clock.now
            do {
                try Task.checkCancellation()
                let content: AgenticContent
                if let schema {
                    let json: String
                    if streaming {
                        let stream = session.streamResponse(to: prompt, schema: schema, options: options)
                        for try await snapshot in stream {
                            try Task.checkCancellation()
                            try yield(.text(snapshot.content.jsonString))
                        }
                        try Task.checkCancellation()
                        json = try await stream.collect().content.jsonString
                    } else {
                        json = try await session.respond(to: prompt, schema: schema, options: options).content
                            .jsonString
                    }
                    guard let value = JSONString(json) else { throw AgenticSessionError.incompleteGeneration }
                    content = .json(value)
                } else {
                    let text: String
                    if streaming {
                        let stream = session.streamResponse(to: prompt, options: options)
                        for try await snapshot in stream {
                            try Task.checkCancellation()
                            try yield(.text(snapshot.content))
                        }
                        try Task.checkCancellation()
                        text = try await stream.collect().content
                    } else {
                        text = try await session.respond(to: prompt, options: options).content
                    }
                    guard !text.isEmpty else { throw AgenticSessionError.incompleteGeneration }
                    content = .text(text)
                }
                try Task.checkCancellation()
                return AgenticResponse(
                    content: content, metadata: metadata(duration: start.duration(to: clock.now), session: session))
            } catch {
                throw Self.map(error)
            }
        }

        private func metadata(duration: Duration, session: LanguageModelSession) -> AgenticExecutionMetadata? {
            let fields = configuration.metadata
            guard !fields.isEmpty else { return nil }
            var promptTokens: Int?
            var completionTokens: Int?
            #if compiler(>=6.4)
                if #available(macOS 27, iOS 27, visionOS 27, *), fields.contains(.tokenUsage) {
                    // This session contains exactly one request, so cumulative usage is per-request.
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

        private static func checkAvailability() throws {
            switch SystemLanguageModel.default.availability {
            case .available: return
            case .unavailable(let reason):
                let message: String
                switch reason {
                case .deviceNotEligible: message = "This device is not eligible for Apple Intelligence."
                case .appleIntelligenceNotEnabled: message = "Apple Intelligence is disabled."
                case .modelNotReady: message = "The local model is not ready."
                @unknown default: message = "The local model is unavailable."
                }
                throw AgenticSessionError.modelUnavailable(reason: message)
            }
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
                        case .unsupportedGenerationGuide:
                            return .unsupportedSchema(reason: "The model rejected a generation constraint.")
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
                case .unsupportedGuide: return .unsupportedSchema(reason: "The model rejected a generation constraint.")
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
