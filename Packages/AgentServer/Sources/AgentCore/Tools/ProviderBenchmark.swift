import Foundation

/// Explicitly opt-in: uses the caller's installed CLI login and makes real model
/// requests. Prints operational measurements only, never prompts or outputs.
public enum ProviderBenchmark {
    public static func run(providerID: String) async throws {
        guard let kind = CLIProvider.Kind(rawValue: providerID) else { throw AgentError("unsupported_provider", "Benchmark requires codex, antigravity or grok.") }
        let executable = kind == .antigravity ? "agy" : kind.rawValue
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentServerBenchmark-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let inputs: [(String, JSONValue)] = [
            ("NewsResearcher", .object([
                "topic": .string("TfL rules for privately owned e-scooters on London public transport"),
                "language": .string("English"),
                "source_url": .string("https://tfl.gov.uk/modes/driving/electric-scooter-rental-trial"),
            ])),
            ("ScriptRefiner", .object([
                "script": .string("INT. WORKSHOP - DAY, 10 seconds. MAYA wears a blue jacket beside a desk. 0–3s: she holds one brass key in her left hand. 3–7s close-up: the key becomes silver in her right hand without a transfer. 7–10s: the key disappears, then she uses it to open the desk lock. Preserve the scene duration and correct continuity."),
                "output_count": .number(1),
            ])),
        ]
        for reuse in [false, true] {
            let registry = AgentRegistry()
            let adapter = CLIProvider(kind: kind, settings: .init(executable: executable, workerReuse: reuse))
            let catalog = ProviderCatalog(providers: [adapter])
            let manager = ExecutionManager(registry: registry, providers: catalog, runtimeRoot: root,
                maxProcesses: 8, timeoutSeconds: 180, providerPoolSize: reuse ? 5 : 0)
            for (agent, input) in inputs {
                for iteration in 0..<(reuse ? 2 : 1) {
                    let began = Date()
                    var row: [String: JSONValue] = ["provider": .string(providerID), "agent": .string(agent),
                        "mode": .string(reuse ? "auto" : "fresh"), "iteration": .number(Double(iteration + 1)),
                        "model": .string("CLI default"), "reasoning_effort": .string("CLI default")]
                    do {
                        let definition = try await registry.resolve(id: agent, version: nil)
                        row["version"] = .string(definition.version)
                        let accepted = try await manager.execute(ExecuteRequest(agentID: agent, provider: providerID, input: input))
                        let deadline = Task {
                            do { try await Task.sleep(for: .seconds(180)) } catch { return }
                            _ = try? await manager.cancel(accepted.id)
                        }
                        for await _ in accepted.events {}
                        deadline.cancel()
                        if let record = await manager.snapshot().records.first(where: { $0.execution_id == accepted.id }) {
                            row["status"] = .string(record.status)
                            row["worker_reused"] = .bool(record.worker_reused ?? false)
                            row["phase_timings"] = .object((record.phase_timings ?? [:]).mapValues(JSONValue.number))
                            if let error = record.error { row["error_code"] = .string(error.code) }
                            if let reasons = record.queue_reasons { row["queue_reasons"] = .array(reasons.map(JSONValue.string)) }
                        }
                    } catch {
                        row["status"] = .string("rejected")
                        row["error_code"] = .string((error as? AgentError)?.code ?? "internal_error")
                    }
                    row["worker_mode"] = .string(adapter.workerReuseMode)
                    row["wall_seconds"] = .number(Date().timeIntervalSince(began))
                    try FileHandle.standardOutput.write(contentsOf: Data((try JSONValue.object(row).text() + "\n").utf8))
                }
            }
            await manager.shutdown(timeoutSeconds: 5)
        }
    }
}
