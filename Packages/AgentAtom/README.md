# AgentAtom

Standalone Swift specifications, operations, and sessions. This package has no
dependency on AgentServer, the Mac app, or sibling packages and can move to its own
repository.

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

Operations depend only on `Spec`. `ModelledSpec` is one way to implement a spec;
operations do not know or care how a spec is implemented. The operation protocol
exposes its associated spec type, the spec instance, and `makeInstructions()` only.
The session reads input from that spec.

`AgenticOperation` requests the spec's output. `FailableAgenticOperation` also
permits the AI to decline with a reason. Both are structs conforming to
`AgenticOperationProtocol`, and both can throw execution errors.

Execution returns a native tuple containing session metadata and the built-in
`Result<String, NSError>` directly, without a custom result type or typealias.

Successful content is the model's unchanged response text. The operation supplies
the spec's JSON schema in its instructions; the model is expected to produce that
JSON directly. The library does not translate the schema into an Apple-specific
schema, decode domain output, unwrap success JSON, re-encode, repair, strip fences,
or otherwise format the answer. Prompted schema adherence is an expectation, not
a guarantee that arbitrary output will decode. The caller decodes it afterward.

```swift
if #available(macOS 26, iOS 26, visionOS 26, *) {
    guard let session = AppleIntelligenceSession(configuration: .init(
        metadata: [.duration, .modelIdentifier]
    )) else {
        return // This device or its local model is unavailable.
    }

    let response = await session.execute(AgenticOperation(spec: spec))
    switch response.content {
    case .success(let json):
        let output = try JSONDecoder().decode(MySpec.Output.self, from: Data(json.utf8))
        // Retain and validate output in the caller.
    case .failure(let failure):
        print(failure.localizedDescription)
    }
}
```

A normal operation returns its response string without interpreting domain JSON.
A failable operation appends the fixed failure schema while creating its final
instructions. Success uses the spec's original schema unchanged. Failure uses:

```json
{"domain":"AgentAtom.Operation","code":422,"reason":"The input is insufficient."}
```

There is no combined schema or success envelope. The original JSONSchema type is
unchanged. The session recognizes the reserved AgentAtom.Operation
failure domain and returns Foundation NSError with code 422 and the reason as its
localized description. Invalid reserved failure responses throw invalidResponse.
All other content is returned as the exact original success string, including
malformed domain JSON for the caller to decode later. That domain is reserved for error responses, rather than ordinary domain output.

Operations use value semantics. Create one per request; there is no reuse tracking,
defensive copying, or mutation policing. Keep reference-backed input and computed
request values stable during execution. Fact checking, list lengths, and other
domain validation belong to the caller, as do retries.

## Instructions

Operations generate instructions through `makeInstructions()` before the session
executes them. A strategy-backed assembler builds normal and failable instruction
formats. Session configuration has no instructions, roles, or spec rules. The spec owns its
initialized instructions. Operations accept only a spec; they add fixed JSON-format
rules in code, without runtime base instructions or instruction overrides.

The spec role, instructions, and output schema are sent as provider instructions.
Input is sent separately as prompt data. A String spec input stays its JSON string
literal, with its original escaping. Instruction assembly expresses precedence;
it does not prove model obedience.

## Sessions and configuration

`AgenticSessionProtocol` directly executes generic operations and associates its
own configuration type. Callers initialize and inject the concrete session they
want; there is no singleton or shared scheduling. Execution returns success or a
mapped NSError. A session without streaming support finishes its snapshot stream
with an unsupported-streaming error and returns the same failure in its result.

`AppleIntelligenceSession` is available at compile time on macOS/iOS/visionOS 26+.
Its failable initializer returns nil if the device, Apple Intelligence settings,
or local model availability prevent initialization. It uses only
`SystemLanguageModel.default`.
The package retains its older deployment minimums. There is no automatic provider
fallback.

Each Apple session handles one active operation; overlap returns a busy failure. Create
independent sessions for concurrency. Each execution uses a fresh provider
conversation. History-enabled behavior is a separate feature.

Apple configuration selects generation temperature and which metadata fields to
return. Temperature is non-optional, defaults to 1, and uses a private generic
property wrapper in the session implementation to clamp to 0...1. NaN uses the default;
infinities clamp to their respective bounds. Response length uses the provider's
context-based limit. See
[Apple's temperature documentation](https://developer.apple.com/documentation/foundationmodels/generationoptions/temperature).
All operations here request JSON and expose
strings; provider-specific image generation is outside this implementation.

Metadata belongs exclusively to the session response and is disabled by default.
The Apple session can report model identifier, duration, and token usage; token
counts use the version-guarded OS 27 SDK usage API. Duration uses a monotonic clock
for generation time, excluding instruction assembly and caller decoding. The model
identifier reports `SystemLanguageModel.default`, not an invented version. The
portable metadata result can carry model tier, reasoning effort, and finish reason
when another session implementation can report them. The provider conversation
contains exactly one request, so token counts are per-request; actual zero is kept.

## Streaming and cancellation

```swift
let stream = await session.stream(AgenticOperation(spec: spec))
for try await snapshot in stream.snapshots {
    print(snapshot) // Replace display content with this cumulative string.
}
let response = await stream.result.value // Final string-or-failure and metadata.
```

Starting a stream starts generation. Snapshots have one consumer and buffer only
the newest string. Intermediate updates may coalesce and need not be prefix
extensions. Partial JSON is not decoded or repaired. Only result() establishes
completed execution; it still does not decode domain output. An error after a
valid-looking partial snapshot remains an execution error.

The session returns a tuple containing the built-in AsyncThrowingStream and a
nonthrowing Swift Task for the final response. Execution failures are mapped once
to the session NSError and returned as Result.failure; the snapshot stream also
finishes with that error. Cancel stream.result directly to stop work,
including when abandoning iteration. Cancellation of the snapshot iterator also
cancels the producer. Awaiting Task.value alone does not propagate cancellation
from the waiter; the caller owns cancellation of that result Task. The session stays busy until its provider call
returns. Buffering bounds snapshot count, not the final string size.

## Errors

Session errors conform to LocalizedError and CustomNSError with stable domain
`AgentAtom.Session` and explicit codes: model unavailable 1001, unsupported streaming
1002, busy 1003, cancelled 1004, context limit 1005, refusal 1006, incomplete response
1007, rate limited 1008, execution failure 1009, invalid failure response 1010. Diagnostic
messages do not copy provider prompts or input. Apple execution errors use
`AgenticSessionError`. AI-declared failure uses
Foundation NSError (domain AgentAtom.Operation, code 422) as result data,
not an execution error. A normal operation does not instruct the AI to use that failure format.

## Structure and validation

New operation/session protocols have their own files, separate from their concrete
implementations and defaults. Existing spec files remain untouched.

The remaining types have distinct roles: two operation structs describe their
allowed outcomes; Swift Result and Foundation NSError carry string-or-failure data; the
native response tuple and portable metadata carry execution details; the Apple actor/configuration own
provider execution; the built-in stream and Task provide progressive delivery and completion.
There are no response/result/stream wrapper types, result aliases, transport content wrappers, schema translator, backend class, or
domain-output conversion layer.

Run `swift build --target AgentAtom` to compile the library. Runnable examples and
validation of generated results belong to consumers, rather than this package.
Existing Phase 2 tests cover specs and schema derivation. New operation,
session, cancellation, platform, and live-model tests are a separate task:
[#88](https://github.com/Khabarwaani/ScriptMakerServer/issues/88).

Implementation [PR #89](https://github.com/Khabarwaani/ScriptMakerServer/pull/89)
addresses [#87](https://github.com/Khabarwaani/ScriptMakerServer/issues/87). It must
remain unmerged until the user explicitly authorizes that PR's merge in chat,
with the authorization verified twice. Checks and inferred intent are insufficient.
