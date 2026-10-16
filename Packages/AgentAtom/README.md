# AgentAtom

> Canonical standalone repository: [abhi266raj/AgentAtom](https://github.com/abhi266raj/AgentAtom),
> release **0.0.1**, licensed AGPL-3.0-only. This directory remains the local
> ScriptMakerServer snapshot; its dependency has not migrated yet. Future package
> development belongs in the standalone repository. Synchronize this snapshot
> only through an explicit reviewed change.
>
> The public repository includes standalone installation instructions and a
> [runnable macOS example](https://github.com/abhi266raj/AgentAtom/tree/0.0.1/Examples/AgentAtomDemo).
> See [publication and migration notes](../../Documentation/docs/AGENTATOM_PUBLICATION.md).
Swift specifications, reusable operations, and sessions.

## Specifications

`Spec` supplies identity, role, instructions, input JSON, and the expected output
JSON schema. `ModelledSpec<Input, Output>` derives JSON from an Encodable input and
schema from a Decodable output. Outputs need neither Encodable nor `@Generable`.
The spec's optional output storage is caller-owned; execution never writes to it.

`JSONString` preserves validated JSON text. Its dynamic initializer is failable;
invalid string literals are programmer errors. Foundation parsing accepts scalars
and null, and can accept extensions such as trailing commas on Apple platforms.

`JSONSchema` derives supported primitive, object, array, string-keyed dictionary,
and optional shapes through pinned TypeDecoder. Objects allow additional domain
keys; optional properties may be absent or null. Recursive/unsupported shapes and
excessive nesting fail derivation. Arbitrary raw-schema construction is not public.
Custom Decodable implementations are not guaranteed to be described completely by
model inspection. Domain validation, enum cases, and numeric-width rules are not
inferred. Existing ModelledSpec defaults use preconditionFailure on conversion
failure; these are programmer preconditions, not recoverable execution errors.

## Operations and results

Operations depend on `Spec` and an injected generic `AgenticSessionProtocol`.
They do not depend on `ModelledSpec` or decode domain output. Each operation
conforms to Swift's `Identifiable` and exposes its spec, `state`, `instructions()`,
and associated `Result` through `AgenticOperationProtocol`.

| Operation | `execute()` result | AI-declared failure allowed |
| --- | --- | --- |
| `AgenticOperation` | `Result<String, AgenticError>` | No |
| `FailableAgenticOperation` | `Result<String, AgenticError>` | Yes |
| `StreamingAgenticOperation` | `AsyncStream<Result<String, AgenticError>>` | No |
| `FailableStreamingAgenticOperation` | `AsyncStream<Result<String, AgenticError>>` | Yes |

All four can encounter provider errors or cancellation. Successful final content
is the session's response string. Operations preserve it unchanged. The caller
decodes and validates domain output afterward; the package never repairs JSON,
strips fences, unwraps success envelopes, or re-encodes domain output. Apple uses
native guided generation and returns `GeneratedContent.jsonString`. Shape enforcement
does not guarantee factual correctness or compliance with semantic instructions.

```swift
if #available(macOS 26, iOS 26, visionOS 26, *) {
    guard let session = AppleIntelligenceSession(configuration: .init(
        metadata: [.duration, .modelIdentifier]
    )) else {
        return
    }

    let operation = AgenticOperation(spec: spec, session: session)
    let response = await operation.execute()
    switch response {
    case .success(let json):
        let output = try JSONDecoder().decode(MySpec.Output.self, from: Data(json.utf8))
        // Retain and validate output in the caller.
    case .failure(let error):
        print(error.localizedDescription)
    }

    let nextResponse = await operation.execute()
    let records = session.executionMetadata
    // Same operation.id; each admitted run has a distinct records entry and executionID.
}
```

## Reuse, identity, and lifecycle

Operations use Identifiable's default ObjectIdentifier, stable for the object's
lifetime across runs. This identity is process-local and may be reused after the
object is deallocated; retain the operation when correlating its records.
Each operation is an actor retaining its immutable spec and session reference.
It owns its active task and execution state directly; callers need no task handle. Assigning another reference
preserves the same operation, identity, and active execution. Construct another
operation for independent identity and lifecycle control. There is no runner.

Call `execute()` again after completion or cancellation cleanup to start another
run. An overlapping call on the same operation returns `busy`. Only the active
producer Task is retained; operations store neither execution IDs nor result history.
They do not enqueue requests or retry automatically.

The session assigns a fresh execution UUID when it admits a run. Its read-only,
thread-safe `executionMetadata` array records the operation's ObjectIdentifier
and execution UUID after that run finishes, including provider failure and cancellation.
Identity is always recorded; configured metrics are optional. Admission failures
and instruction-assembly failures do not create an execution ID or record.

```swift
let latest = session.executionMetadata.last
let id = operation.id
let runs = session.executionMetadata.filter { $0.operationID == id }
```

`await operation.cancel()` cooperatively cancels the active producer. Cancellation
of a task awaiting a non-streaming operation also cancels its producer. Cancellation
does not free the session until its provider call returns and cleanup completes.
Cancelling an idle operation is a no-op and does not prevent a later execution.

`try await operation.pause()` and `resume()` delegate to the session for the active
operation. They throw `notRunning` when idle. Unsupported sessions throw
`unsupported` without changing the active execution.
`state` is ready, running, paused, cancelling, completed, cancelled, or failed.
Cancelling reserves the active slot until cleanup finishes. Terminal states permit
another execution. Pause/resume recheck the active task after suspension so a late
provider response cannot change a later run's state.
The Apple session has no native generation pause/resume support and uses these
explicit unsupported errors.

## Instructions and declared failures

Operations assemble final instructions on every call using the generic
strategy implementations; no forwarding-only assembler wrapper is needed. They send the spec role, rules, and original output
schema as provider instructions, with input JSON sent separately as prompt data.
They also send the response schema separately for provider-native generation.
Failable strategies add the reserved failure alternative to that request schema;
the spec schema itself remains unchanged.
A String input retains its JSON quoting and escaping. Session configuration does
not own roles, rules, or instruction overrides.

Failable operations append an alternative failure schema derived from a
Decodable shape. The model must use this reserved failure format:

```json
{"domain":"AgentAtom.Operation","code":422,"reason":"The input is insufficient."}
```

The original success schema remains unchanged. Failable operations convert a valid
reserved failure response into `generationFailed(reason:)`; standard operations
return `operationFailed` for it. Malformed reserved failure responses are also
invalid. All other final text passes through unchanged, including malformed domain
JSON for the caller to decode. Failure inspection uses one JSONDecoder pass. Malformed reserved failures remain
errors; unrelated domain output still passes through unchanged.
Intermediate streaming snapshots are not decoded.

Keep reference-backed spec input and computed request values stable during a run.
Domain constraints, fact checking, output decoding, and retry decisions belong to
the caller.

## Sessions and configuration

The class-bound, Sendable session protocol supplies generation primitives accepting finalized
instructions, input, response schema JSON, and an operation ObjectIdentifier. Streaming forwards snapshots through a
nonescaping async callback and returns the final result. Sessions own provider access,
configuration, per-run IDs, and execution records. Operations own lifecycle control
and final failure interpretation.
Sessions reject cancellation before admission and rely on provider cancellation during generation; operations
use that result without checking cancellation again after the session returns.
Non-streaming caller cancellation reaches the worker through a cancellation handler.
Streaming checks the caller before launching its independent producer; provider
stream cancellation and consumer termination handle the active run without snapshot polling.

`AppleIntelligenceSession` is a final Sendable class, compiled only where FoundationModels is supported
and is available on macOS/iOS/visionOS 26+. Its failable initializer checks device,
settings, and model readiness once. It uses `SystemLanguageModel.default` and one
file-level platform guard. The package retains its older deployment minimums.

Normal and streaming generation call the provider directly and share admission,
per-run identity, error mapping, and metadata helpers.
A mutex protects admission and record snapshots; provider work and callbacks run
outside the lock. The session does not create producer tasks.

The Apple adapter decodes the request schema with Apple's native Codable
`GenerationSchema`, supplying required object ordering and alternative names.
It uses native schema-based `respond`/`streamResponse` and exposes the generated
content's native JSON string, without requiring consumer output to be `@Generable`.
Objects use Apple's closed-property representation. Supported constraints include
required fields, nullable alternatives, arrays, string enums, numeric bounds,
and array counts. Unsupported keywords (including `format` and `contentEncoding`)
and non-string enums fail before admission instead of silently losing constraints.
The caller's spec owns domain rules such as result count; AgentAtom has no
KeyPoints-specific rules, count checks, extra feasibility calls, or automatic retries.

One Apple session admits one generation at a time; overlap returns `busy`. Use
independent sessions for concurrency. Every run uses a fresh provider conversation;
execution records are diagnostic metadata, not conversation history.

Configuration is fixed at initialization. Temperature defaults to 1 and clamps to
0...1 using Swift's min/max; NaN uses the default and infinities
clamp to the bounds. Response length follows the provider context limit.

`AgenticExecutionMetadata.Fields` is an OptionSet selecting independent metrics,
for example `metadata: [.duration, .tokenUsage]`. Optional metrics default to disabled.
Apple can collect model identifier, monotonic
generation duration, and token usage. Token counts use the guarded OS 27 SDK API;
unavailable counts stay absent and actual zero is preserved. The identifier is
`SystemLanguageModel.default`, not an invented model version. Unpopulated tier,
reasoning-effort, and finish-reason fields are omitted.

## Streaming

```swift
let operation = FailableStreamingAgenticOperation(spec: spec, session: session)
let stream = await operation.execute()
for await result in stream {
    switch result {
    case .success(let snapshot):
        print(snapshot) // Replace display content with the cumulative text.
    case .failure(let error):
        print(error.localizedDescription)
    }
}
```

Each stream has one consumer and buffers only its newest result. Intermediate
successes contain cumulative snapshots and can coalesce; they need not be prefix
extensions. After normal completion, the last element is the final success or
failure. Do not decode a partial snapshot as a completed result.

Call `await operation.cancel()` to stop generation without losing the consumer's
ability to receive the final cancellation failure. Cancelling the consuming task
also cancels the producer but terminates delivery, so its last received snapshot
might remain partial. Breaking the loop alone does not guarantee prompt cancellation.
Call `await operation.cancel()` before breaking early when generation should stop.
A rerun is available after the producer finishes cleanup.

## Errors and validation

`AgenticError` is a Sendable, Equatable Swift error with LocalizedError
descriptions. Its six cases are operationFailed(reason:), generationFailed(reason:), cancelled,
busy, notRunning, and unsupported. Provider, instruction, and response failures use
operationFailed with a diagnostic reason; AI-declared failure retains its reason separately. Public results do not require
NSError. Provider errors are mapped
once at the session boundary; the operation interprets only the reserved final
model-failure format.

Protocol extensions live with their declarations. Concrete implementations and
the typed error occupy separate files.
Each worker completes its lifecycle and releases its task before returning a result.
The four operation actors own their tasks directly; an internal actor protocol shares
lifecycle and execution defaults without adding a controller. Normal and streaming
execution each have one implementation; concrete actors only provide their stored
state, strategy, and a forwarding execute() method. Immutable generic strategies
share instruction assembly and final failure interpretation. The final session
class shares admission and completion helpers; it has no runner or unchecked Sendable conformance.
Concrete Result aliases witness the protocol using native Result or AsyncStream.
No public execution handle, response wrapper, queue, or schema translator is introduced.
Existing Spec, ModelledSpec, and JSONSchema implementations are unchanged.

Run `swift build --package-path Packages/AgentAtom` to compile and
`swift test --package-path Packages/AgentAtom` for deterministic validation.
The separate test task [#88](https://github.com/Khabarwaani/ScriptMakerServer/issues/88)
adds operation/session contracts and the original KeyPoints sample. Its live failures
in [#91](https://github.com/Khabarwaani/ScriptMakerServer/issues/91) motivated native
guided generation in the same validation PR. See [Tests/README.md](Tests/README.md)
for commands, verified platforms, and the limits of those checks.

Implementation [PR #89](https://github.com/Khabarwaani/ScriptMakerServer/pull/89)
was merged separately; [PR #92](https://github.com/Khabarwaani/ScriptMakerServer/pull/92)
contains the contract tests and native generation fix.
