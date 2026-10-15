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

`AgenticOperation` requests the spec's output. `FailableAgenticOperation` also
permits the AI to decline with a reason. Both are structs conforming to
`AgenticOperationProtocol`, and both can throw execution errors.

Execution returns `AgenticResponse` containing session metadata and the built-in
`Result<String, NSError>` directly, without a custom result type or typealias.

Successful content is the model's unchanged response text. The operation supplies
the spec's JSON schema in its instructions; the model is expected to produce that
JSON directly. The library does not translate the schema into an Apple-specific
schema, decode domain output, unwrap success JSON, re-encode, repair, strip fences,
or otherwise format the answer. Prompted schema adherence is an expectation, not
a guarantee that arbitrary output will decode. The caller decodes it afterward.

```swift
guard let session = AppleIntelligenceSession(configuration: .init(
    metadata: [.duration, .modelIdentifier], maximumResponseTokens: 512
)) else {
    return // Unsupported OS/device, unavailable model, or invalid configuration.
}

let response = try await session.execute(AgenticOperation(spec: spec))
switch response.content {
case .success(let json):
    let output = try JSONDecoder().decode(MySpec.Output.self, from: Data(json.utf8))
    // Retain and validate output in the caller.
case .failure(let failure):
    print(failure.localizedDescription)
}
```

A normal operation returns its response string without interpreting domain JSON.
A failable operation appends the fixed failure schema while creating its final
instructions. Success uses the spec's original schema unchanged. Failure uses:

```json
{"domain":"AgentAtom.Operation","code":422,"reason":"The input is insufficient."}
```

There is no combined schema or success envelope. The original JSONSchema type is
unchanged. A failable operation recognizes only the reserved AgentAtom.Operation
failure domain and returns Foundation NSError with code 422 and the reason as its
localized description. Invalid reserved failure responses throw invalidResponse.
All other content is returned as the exact original success string, including
malformed domain JSON for the caller to decode later. A spec using that reserved
failure domain as ordinary output should use a normal operation.

Operations use value semantics. Create one per request; there is no reuse tracking,
defensive copying, or mutation policing. Keep reference-backed input and computed
request values stable during execution. Fact checking, list lengths, and other
domain validation belong to the caller, as do retries.

## Instructions

Operations generate instructions through makeInstructions() before the session executes them. Session
configuration has no instructions, roles, or spec rules. The spec owns its
initialized instructions. Operations accept only a spec; they add fixed JSON-format
rules in code, without runtime base instructions or instruction overrides.

The spec role, instructions, and output schema are sent as provider instructions.
Input is sent separately as prompt data. A String spec input stays its JSON string
literal, with its original escaping. Instruction assembly expresses precedence;
it does not prove model obedience.

## Sessions and configuration

`AgenticSessionProtocol` directly executes an operation. Callers initialize and
inject the concrete session they want; there is no singleton or shared scheduling.
The protocol has no common configuration type. Default streaming throws an explicit
unsupported-streaming error for implementations that do not provide it.

`AppleIntelligenceSession.init?` returns nil if configuration, SDK, OS, device,
Apple Intelligence settings, or local model availability prevent initialization.
It uses only `SystemLanguageModel.default`, requires macOS/iOS/visionOS 26+, and
rechecks model availability during execution. The package retains its older
deployment minimums. There is no automatic provider fallback.

Each Apple session handles one active operation; overlap throws busy. Create
independent sessions for concurrency. Each execution uses a fresh provider
conversation. History-enabled behavior is a separate feature.

Concrete configuration selects generation temperature, response token budget, and
which metadata fields to return. All operations here request JSON and expose
strings; provider-specific image generation is outside this implementation.

Metadata belongs exclusively to the session response and is disabled by default.
Enabled but unavailable fields remain nil. Duration uses a monotonic clock for
generation time, excluding instruction assembly and caller decoding. The model
identifier reports the selected SystemLanguageModel.default, not an invented
version. Model tier, reasoning effort, and finish reason remain nil when unknown.
Token counts use the version-guarded OS 27 SDK usage API. The provider conversation
contains exactly one request, so those counts are per-request; actual zero is kept.

## Streaming and cancellation

```swift
let stream = try await session.stream(AgenticOperation(spec: spec))
for try await snapshot in stream.snapshots {
    print(snapshot) // Replace display content with this cumulative string.
}
let response = try await stream.result.value // Final string-or-failure and metadata.
```

Starting a stream starts generation. Snapshots have one consumer and buffer only
the newest string. Intermediate updates may coalesce and need not be prefix
extensions. Partial JSON is not decoded or repaired. Only result() establishes
completed execution; it still does not decode domain output. An error after a
valid-looking partial snapshot remains an execution error.

The session returns a tuple containing the built-in AsyncThrowingStream and a
Swift Task for the final response. Cancel stream.result directly to stop work,
including when abandoning iteration. Cancellation of the snapshot iterator also
cancels the producer. Awaiting Task.value alone does not propagate cancellation
from the waiter; the caller owns cancellation of that result Task. The session stays busy until its provider call
returns. Buffering bounds snapshot count, not the final string size; configure a
response token budget appropriate to the application.

## Errors

Session errors conform to LocalizedError and CustomNSError with stable domain
`AgentAtom.Session` and explicit codes: model unavailable 1001, unsupported streaming
1002, busy 1003, cancelled 1004, context limit 1005, refusal 1006, incomplete response
1007, rate limited 1008, execution failure 1009, invalid failure response 1010. Diagnostic
messages do not copy provider prompts or input. AI-declared failure uses Foundation NSError (domain AgentAtom.Operation, code 422) as result data,
not an execution error. A normal operation never permits that result alternative.

## Structure and validation

New operation/session protocols have their own files, separate from their concrete
implementations and defaults. Existing spec files remain untouched. The spec, example execution, and caller decoding are separated too.

The remaining types have distinct roles: two operation structs describe their
allowed outcomes; Swift Result and Foundation NSError carry string-or-failure data; the
response and metadata carry execution details; the Apple actor/configuration own
provider execution; the built-in stream and Task provide progressive delivery and completion.
There are no transport content wrappers, schema translator, backend class, or
domain-output conversion layer.

Run `swift build` to compile the package and public-import example. Run
`swift run KeyPointsExample` explicitly on a supported device to use the local
model. The caller decodes the returned string and checks that there are three
points. Existing Phase 2 tests cover specs and schema derivation. New operation,
session, cancellation, platform, and live-model tests are a separate task:
[#88](https://github.com/Khabarwaani/ScriptMakerServer/issues/88).

Implementation [PR #89](https://github.com/Khabarwaani/ScriptMakerServer/pull/89)
addresses [#87](https://github.com/Khabarwaani/ScriptMakerServer/issues/87). It must
remain unmerged until the user explicitly authorizes that PR's merge in chat,
with the authorization verified twice. Checks and inferred intent are insufficient.
