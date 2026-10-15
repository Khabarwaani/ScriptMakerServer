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
            to input: String, instructions: String, schema: JSONString, for operation: ObjectIdentifier
        ) async -> Result<String, AgenticError> {
            do {
                let schema = try Self.generationSchema(from: schema)
                let run = try begin(instructions: instructions, for: operation)
                defer { finish(run) }
                let response = try await run.model.respond(to: input, schema: schema, options: run.options)
                return .success(response.content.jsonString)
            } catch {
                return .failure(map(error))
            }
        }

        public func stream(
            to input: String, instructions: String, schema: JSONString, for operation: ObjectIdentifier,
            yield: @Sendable (String) async -> Void
        ) async -> Result<String, AgenticError> {
            do {
                let schema = try Self.generationSchema(from: schema)
                let run = try begin(instructions: instructions, for: operation)
                defer { finish(run) }
                let stream = run.model.streamResponse(to: input, schema: schema, options: run.options)
                for try await snapshot in stream {
                    await yield(snapshot.content.jsonString)
                }
                let response = try await stream.collect()
                return .success(response.content.jsonString)
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

        // Apple's native Codable schema requires object order and named alternatives.
        static func generationSchema(from schema: JSONString) throws -> GenerationSchema {
            let object = try JSONSerialization.jsonObject(with: Data(schema.rawValue.utf8))
            var index = 0
            let prepared = try prepare(object, index: &index)
            let data = try JSONSerialization.data(withJSONObject: prepared, options: [.sortedKeys])
            return try JSONDecoder().decode(GenerationSchema.self, from: data)
        }

        private static func prepare(_ value: Any, index: inout Int) throws -> Any {
            guard var schema = value as? [String: Any] else {
                throw AgenticError.operationFailed(reason: "Expected a response schema object.")
            }
            let name = "AgentAtomSchema\(index)"
            index += 1
            let supported: Set<String> = [
                "type", "properties", "required", "items", "anyOf", "additionalProperties",
                "title", "description", "x-order", "enum", "minimum", "maximum", "minItems", "maxItems"
            ]
            if let key = Set(schema.keys).subtracting(supported).min() {
                throw AgenticError.operationFailed(reason: "Apple guided generation does not support schema constraint: \(key).")
            }
            if schema["enum"] != nil, schema["type"] as? String != "string" {
                throw AgenticError.operationFailed(reason: "Apple guided generation supports enum constraints only for strings.")
            }
            if let properties = schema["properties"] as? [String: Any] {
                var ordered: [String: Any] = [:]
                for (key, child) in properties.sorted(by: { $0.key < $1.key }) {
                    ordered[key] = try prepare(child, index: &index)
                }
                schema["properties"] = ordered
                schema["title"] = schema["title"] ?? name
                schema["x-order"] = properties.keys.sorted()
                schema["additionalProperties"] = false
                schema["required"] = schema["required"] ?? []
            }
            if let choices = schema["anyOf"] as? [Any] {
                schema["title"] = schema["title"] ?? name
                schema["anyOf"] = try choices.map { child in
                    try prepare(child, index: &index)
                }
            }
            for key in ["items", "additionalProperties"] {
                if let child = schema[key] as? [String: Any] {
                    schema[key] = try prepare(child, index: &index)
                }
            }
            return schema
        }

        private func map(_ error: any Error) -> AgenticError {
            if error is CancellationError { return .cancelled }
            return (error as? AgenticError) ?? .operationFailed(reason: error.localizedDescription)
        }
    }
#endif
