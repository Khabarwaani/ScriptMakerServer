import Foundation
import Testing

@testable import AgentCore

@Test func antigravityStreamsTextAndPrefersStructuredOutput() async throws {
    let parser = ProviderAccumulator(kind: .antigravity)
    let update = try await parser.consume(
        #"{"event":"step_update","step_update":{"step_type":"agent_response","state":"ACTIVE","text_delta":"partial"}}"#
    )
    #expect(update == .text("partial"))
    _ = try await parser.consume(
        #"{"event":"result","result":{"status":"SUCCESS","response":"{\"result\":\"ok\",\"toolAction\":\"provider metadata\"}","structured_output":{"result":"ok"}}}"#
    )
    #expect(try await parser.finalResult() == .object(["result": .string("ok")]))
}

@Test func antigravityToolProgressDoesNotExposeArguments() async throws {
    let parser = ProviderAccumulator(kind: .antigravity)
    let event = try await parser.consume(
        #"{"event":"step_update","step_update":{"step_type":"tool","state":"ACTIVE","tool_info":{"parameters":{"secret":"do-not-copy"}}}}"#
    )
    guard case .progress(let progress) = event else {
        Issue.record("Expected provider progress")
        return
    }
    #expect(!(try progress.text()).contains("do-not-copy"))
    await #expect(throws: AgentError.self) { try await parser.finalResult() }
}

@Test func grokStreamsPartialMessagesAndRejectsProviderFailure() async throws {
    let parser = ProviderAccumulator(kind: .grok)
    #expect(
        try await parser.consume(
            #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"text":"hello"}}}"#)
            == .text("hello"))
    _ = try await parser.consume(#"{"type":"result","is_error":false,"result":"{\"result\":\"hello\"}"}"#)
    #expect(try await parser.finalResult()["result"] == .string("hello"))
    let failure = ProviderAccumulator(kind: .grok)
    _ = try await failure.consume(#"{"type":"result","is_error":true}"#)
    await #expect(throws: AgentError.self) { try await failure.finalResult() }
}

actor LineCollector {
    var lines: [String] = []
    func add(_ line: String) { lines.append(line) }
}

@Test func processRunnerDeliversIncrementalOutput() async throws {
    let collector = LineCollector()
    let text = try await ProcessRunner().run(
        executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["first\nsecond\n"],
        timeoutSeconds: 10
    ) { line in await collector.add(line) }
    #expect(text == "first\nsecond\n")
    #expect(await collector.lines == ["first", "second"])
}

@Test func processCancellationConfirmsTermination() async throws {
    let runner = ProcessRunner()
    let task = Task {
        try await runner.run(
            executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeoutSeconds: 60)
    }
    for _ in 0..<100 {
        if runner.processID != nil { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(runner.processID != nil)
    runner.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(runner.processID == nil)
}

@Test func processTimeoutIsDistinctFromUserCancellation() async throws {
    do {
        _ = try await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeoutSeconds: 1)
        Issue.record("Expected a timeout")
    } catch let error as AgentError { #expect(error.code == "execution_timeout") }
}

@Test func antigravityTransportAnnotationsAreSeparateFromAgentFields() throws {
    let schema = try JSONValue.parse(
        #"{"type":"object","additionalProperties":false,"required":["summary"],"properties":{"summary":{"type":"string"}}}"#
    )
    let providerResult = try JSONValue.parse(
        #"{"summary":"Research complete","toolAction":"Finalize","toolSummary":"Research"}"#)
    let result = CLIProvider.removeAntigravityToolAnnotations(providerResult, schema: schema)
    try OutputValidator.validate(result, schema: schema)
    #expect(result == .object(["summary": .string("Research complete")]))
    let invalid = try JSONValue.parse(#"{"summary":"Research complete","unexpected":"must fail"}"#)
    #expect(throws: AgentError.self) {
        try OutputValidator.validate(
            CLIProvider.removeAntigravityToolAnnotations(invalid, schema: schema), schema: schema)
    }
}

@Test func codexFailureEventCannotBeReportedAsSuccess() async throws {
    let parser = ProviderAccumulator(kind: .codex)
    _ = try await parser.consume(#"{"type":"turn.failed","error":{"message":"failure"}}"#)
    await #expect(throws: AgentError.self) { try await parser.checkOutcome() }
}

@Test func processRunnerIncludesStandardSearchPathsInChildEnvironment() async throws {
    let output = try await ProcessRunner().run(
        executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: [], timeoutSeconds: 10)
    let pathLine = output.components(separatedBy: "\n").first(where: { $0.hasPrefix("PATH=") }) ?? ""
    #expect(pathLine.contains("/opt/homebrew/bin") || pathLine.contains("/usr/local/bin"))
    #expect(pathLine.contains("/usr/bin"))
}

