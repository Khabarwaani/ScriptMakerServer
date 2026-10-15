# AgentAtom

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
exposes its UUID, spec, `isExecuting`, final-instruction method, and an associated
execution-result type through `AgenticOperationProtocol`.

| Operation | `execute()` result | AI-declared failure allowed |
| --- | --- | --- |
| `AgenticOperation` | `Result<String, AgenticOperationError>` | No |
| `FailableAgenticOperation` | `Result<String, AgenticOperationError>` | Yes |
| `StreamingAgenticOperation` | `AsyncStream<Result<String, AgenticOperationError>>` | No |
| `FailableStreamingAgenticOperation` | `AsyncStream<Result<String, AgenticOperationError>>` | Yes |

All four can encounter provider errors or cancellation. Successful final content
is the model's unchanged response text. The caller decodes and validates domain
output afterward; the package never repairs JSON, strips fences, unwraps success
envelopes, re-encodes output, or translates schemas into an Apple-specific schema.
Prompted schema adherence does not guarantee that arbitrary model output decodes.

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
    let records = await session.executionMetadata
    // Same operation.id; each admitted run has a distinct records entry and executionID.
}
```

## Reuse, identity, and lifecycle

An operation's UUID is assigned at initialization and remains stable across runs.
Its immutable spec and session reference are retained. Operations are structs
containing a shared private lifecycle actor: copying a value preserves the same
logical operation, UUID, and active execution. Construct another operation for
independent identity and lifecycle control.

Call `execute()` again after completion or cancellation cleanup to start another
run. An overlapping call on the same operation returns `busy`. Only the active
producer Task is retained; operations store neither execution IDs nor result history.
They do not enqueue requests or retry automatically.

The session assigns a fresh execution UUID when it admits a run. Its read-only,
asynchronously accessible `executionMetadata` array records the operation UUID
and execution UUID after that run finishes, including provider failure and cancellation.
Identity is always recorded; configured metrics are optional. Admission failures
and instruction-assembly failures do not create an execution ID or record.

```swift
let latest = await session.executionMetadata.last
let runs = await session.executionMetadata.filter { $0.operationID == operation.id }
```

`await operation.cancel()` cooperatively cancels the active producer. Cancellation
of a task awaiting a non-streaming operation also cancels its producer. Cancellation
does not free the session until its provider call returns and cleanup completes.
Cancelling an idle operation is a no-op and does not prevent a later execution.

`try await operation.pause()` and `resume()` delegate to the session for the active
operation. They throw `notRunning` when idle. Unsupported sessions throw
`cannotPause` or `cannotResume` without changing the active execution.
`isExecuting` remains true while a run is active, including when a provider pauses it.
The Apple session has no native generation pause/resume support and uses these
explicit unsupported errors.

## Instructions and declared failures

Operations assemble final instructions on every call using the generic
strategy-backed assembler. They send the spec role, rules, and original output
schema as provider instructions, with input JSON sent separately as prompt data.
A String input retains its JSON quoting and escaping. Session configuration does
not own roles, rules, or instruction overrides.

Failable operations append an alternative failure schema derived from a
Decodable shape. The model must use this reserved failure format:

```json
{"domain":"AgentAtom.Operation","code":422,"reason":"The input is insufficient."}
```

The original success schema remains unchanged. Failable operations convert a valid
reserved failure response into `generationFailed(reason:)`; standard operations
return `invalidResponse` for it. Malformed reserved failure responses are also
invalid. All other final text passes through unchanged, including malformed domain
JSON for the caller to decode. Intermediate streaming snapshots are not decoded.

Keep reference-backed spec input and computed request values stable during a run.
Domain constraints, fact checking, output decoding, and retry decisions belong to
the caller.

## Sessions and configuration

The session protocol supplies generation primitives accepting finalized
instructions, input, and an operation UUID. Streaming forwards snapshots through a
nonescaping async callback and returns the final result. Sessions own provider access,
configuration, per-run IDs, and execution records. Operations own lifecycle control
and final failure interpretation.

`AppleIntelligenceSession` is compiled only where FoundationModels is supported
and is available on macOS/iOS/visionOS 26+. Its failable initializer checks device,
settings, and model readiness once. It uses `SystemLanguageModel.default` and one
file-level platform guard. The package retains its older deployment minimums.

One Apple session admits one generation at a time; overlap returns `busy`. Use
independent sessions for concurrency. Every run uses a fresh provider conversation;
execution records are diagnostic metadata, not conversation history.

Configuration is fixed at initialization. Temperature defaults to 1 and clamps to
0...1 using a private generic property wrapper; NaN uses the default and infinities
clamp to the bounds. Response length follows the provider context limit.

Optional metrics default to disabled. Apple can collect model identifier, monotonic
generation duration, and token usage. Token counts use the guarded OS 27 SDK API;
unavailable counts stay absent and actual zero is preserved. The identifier is
`SystemLanguageModel.default`, not an invented model version. Other sessions can
populate the portable tier, reasoning-effort, and finish-reason fields.

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
A rerun is available after the producer finishes cleanup.

## Errors and validation

`AgenticOperationError` is a Sendable, Equatable Swift error with LocalizedError
descriptions. It covers model-declared generation failure with a reason, provider
failures, cancellation, busy admission, invalid instructions/responses, and lifecycle
capability errors. Public results do not require NSError. Provider errors are mapped
once at the session boundary; the operation interprets only the reserved final
model-failure format.

Protocols, implementations, defaults, and the typed error occupy separate files.
The four operation structs share one private lifecycle actor. No public execution
handle, response wrapper, result alias, queue, or schema translator is introduced.
Existing Spec, ModelledSpec, and JSONSchema implementations are unchanged.

Run `swift build --package-path Packages/AgentAtom` to compile. Automated operation,
session, cancellation, platform, and live-model tests remain a separate task:
[#88](https://github.com/Khabarwaani/ScriptMakerServer/issues/88). Coverage must include
reruns with distinct execution IDs, shared operation identity, overlap rejection,
cancellation cleanup, unsupported lifecycle controls, and all four result modes.

Implementation [PR #89](https://github.com/Khabarwaani/ScriptMakerServer/pull/89)
addresses [#87](https://github.com/Khabarwaani/ScriptMakerServer/issues/87). It must
remain unmerged until the user explicitly authorizes that PR's merge in chat,
with the authorization verified twice. Checks and inferred intent are insufficient.
