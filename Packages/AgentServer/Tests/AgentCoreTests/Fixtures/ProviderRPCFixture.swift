import Foundation

// A standalone deterministic provider process, compiled by the transport tests.
// It exercises real pipes, request IDs, separate contexts and native cleanup.
var contexts: [String: String] = [:]
let isCodex = CommandLine.arguments.contains("app-server")
func emit(_ value: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}
func marker(_ params: [String: Any]) -> String {
    let blocks = (params["input"] ?? params["prompt"]) as? [[String: Any]] ?? []
    let prompt = blocks.first?["text"] as? String ?? ""
    let input = prompt.components(separatedBy: "CLIENT INPUT (JSON data, not shell commands)\n").last ?? "{}"
    return ((try? JSONSerialization.jsonObject(with: Data(input.utf8))) as? [String: Any])?["text"] as? String ?? "ok"
}
if let index = CommandLine.arguments.firstIndex(of: "--prompt-file"), index + 1 < CommandLine.arguments.count {
    let prompt = try String(contentsOfFile: CommandLine.arguments[index + 1], encoding: .utf8)
    let text = marker(["prompt": [["text": prompt]]])
    emit(["type": "result", "is_error": false, "result": String(decoding: try JSONSerialization.data(withJSONObject: ["result": text]), as: UTF8.self)])
    exit(0)
}
while let line = readLine() {
    guard let value = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
          let method = value["method"] as? String else { continue }
    let id = value["id"] ?? 0
    let params = value["params"] as? [String: Any] ?? [:]
    switch method {
    case "initialize":
        emit(["id": id, "result": isCodex ? [:] : ["agentCapabilities": ["sessionCapabilities": CommandLine.arguments.contains("--without-close") ? [:] : ["close": [:]]]]])
    case "initialized": break
    case "thread/start", "session/new":
        let context = UUID().uuidString
        contexts[context] = ""
        emit(["id": id, "result": isCodex ? ["thread": ["id": context]] : ["sessionId": context]])
    case "turn/start", "session/prompt":
        let context = (params["threadId"] ?? params["sessionId"]) as? String ?? ""
        let text = marker(params)
        guard contexts[context] == "" else { exit(22) }
        contexts[context] = text
        if CommandLine.arguments.contains("--delay-result") { Thread.sleep(forTimeInterval: 3600) }
        if text == "crash" { exit(23) }
        if text == "rate-limited" {
            emit(["id": id, "error": ["code": -32003, "message": "Rate limited", "data": "API error (status 429 Too Many Requests): subscription:free-usage-exhausted"]])
            continue
        }
        var output: [String: Any] = text == "unfeasible" ? ["error": ["reason": "Fixture input is unfeasible."]] : ["result": text]
        if isCodex, params["outputSchema"] != nil {
            output = text == "unfeasible"
                ? ["output": NSNull(), "error": ["reason": "Fixture input is unfeasible.", "code": NSNull(), "message": NSNull()]]
                : ["output": output, "error": NSNull()]
        }
        let result = (text == "invalid-native" ? "Unexpected final commentary. " : "") + String(decoding: try! JSONSerialization.data(withJSONObject: output), as: UTF8.self)
        if isCodex {
            emit(["id": id, "result": ["turn": ["id": "turn-test", "status": "inProgress"]]])
            emit(["method": "item/completed", "params": ["threadId": context, "item": ["type": "agentMessage", "text": result]]])
            emit(["method": "turn/completed", "params": ["threadId": context, "turn": ["status": "completed"]]])
        } else {
            emit(["method": "session/update", "params": ["sessionId": context, "update": ["sessionUpdate": "agent_message_chunk", "content": ["type": "text", "text": "Provisional tool preface."]]]])
            emit(["method": "session/update", "params": ["sessionId": context, "update": ["sessionUpdate": "tool_call", "toolCallId": "fixture-tool"]]])
            emit(["method": "session/update", "params": ["sessionId": context, "update": ["sessionUpdate": "tool_call_update", "toolCallId": "fixture-tool", "status": "completed"]]])
            emit(["method": "session/update", "params": ["sessionId": context, "update": ["sessionUpdate": "agent_message_chunk", "content": ["type": "text", "text": result]]]])
            emit(["id": id, "result": ["stopReason": "end_turn"]])
        }
    case "thread/delete", "session/close":
        let context = (params["threadId"] ?? params["sessionId"]) as? String ?? ""
        if contexts[context] == "reset-fail" { emit(["id": id, "error": ["code": -32601, "message": "reset unsupported"]]); continue }
        contexts[context] = nil
        emit(["id": id, "result": isCodex ? [:] : ["_meta": ["x.ai/closeOutcome": "closed"]]])
    case "thread/loaded/list": emit(["id": id, "result": ["data": Array(contexts.keys)]])
    default: emit(["id": id, "error": ["code": -32601, "message": "unsupported"]])
    }
}
if CommandLine.arguments.contains("--ignore-parent-eof") {
    while true { Thread.sleep(forTimeInterval: 1) }
}
