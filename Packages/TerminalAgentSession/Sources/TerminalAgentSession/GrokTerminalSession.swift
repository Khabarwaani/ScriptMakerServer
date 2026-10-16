import Foundation
import AgentAtom

/// An `AgentAtom.AgenticSessionProtocol` implementation driving Grok CLI (`grok`).
public final class GrokTerminalSession: TerminalSessionProtocol {
    public var configuration: TerminalAgentConfiguration { engine.configuration }
    public var executionMetadata: [AgenticExecutionMetadata] { engine.executionMetadata }

    public typealias Configuration = TerminalAgentConfiguration
    private let engine: TerminalSessionEngine

    public init?(configuration: Configuration = Configuration(executablePath: "grok")) {
        guard let engine = TerminalSessionEngine(configuration: configuration) else { return nil }
        self.engine = engine
    }

    public func clearMemory() {
        engine.clearMemory()
    }

    public func purgeMemory() {
        engine.purgeMemory()
    }

    public func respond(
        to input: String,
        instructions: String,
        schema: JSONString,
        for operation: ObjectIdentifier
    ) async -> Result<String, AgenticError> {
        await stream(to: input, instructions: instructions, schema: schema, for: operation, yield: { _ in })
    }

    public func stream(
        to input: String,
        instructions: String,
        schema: JSONString,
        for operation: ObjectIdentifier,
        yield: @Sendable (String) async -> Void
    ) async -> Result<String, AgenticError> {
        var arguments: [String] = [
            "--output-format", "streaming-messages-json",
            "--schema", schema.rawValue
        ]
        if let model = configuration.model {
            arguments += ["--model", model]
        }
        arguments += configuration.extraArguments
        let prompt = "\(instructions)\n\nInput:\n\(input)"
        arguments.append(prompt)

        return await engine.runStreamedExecution(
            arguments: arguments,
            operation: operation,
            defaultModel: "grok",
            lineHandler: { line in
                if let data = line.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    var yieldChunk: String?
                    var extracted: String?
                    if let delta = obj["delta"] as? String {
                        yieldChunk = delta
                    } else if let content = obj["content"] as? String {
                        yieldChunk = content
                    }
                    if let finalResult = obj["result"] as? String {
                        extracted = finalResult
                    } else if let finalObj = obj["result"] {
                        if let resData = try? JSONSerialization.data(withJSONObject: finalObj, options: [.sortedKeys]) {
                            extracted = String(decoding: resData, as: UTF8.self)
                        }
                    }
                    return (extracted: extracted, yieldChunk: yieldChunk)
                } else {
                    let isJSON = line.hasPrefix("{") && line.hasSuffix("}")
                    return (extracted: isJSON ? line : nil, yieldChunk: line)
                }
            },
            yield: yield
        )
    }
}
