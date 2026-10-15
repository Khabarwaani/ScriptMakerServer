# AgentAtom

A standalone Swift package for provider-independent specifications, operations, and sessions. This
directory can move to a separate repository without changing its source or dependency
paths. It has no dependency on AgentServer or sibling packages.

## Public contract

`Spec` exposes static `Identity` (id, name, version), role, and output schema.
Each instance supplies instructions and validated input JSON. Both JSON properties
are non-optional and non-throwing.

`ModelledSpec<Input, Output>` adds an `Encodable & Sendable` input and a
`Decodable & Sendable` output and supplies both JSON properties by default.
Output models need no additional schema protocol, annotation, or Encodable conformance.
Conformers own a mutable optional output property, initially nil, to retain a decoded result.

```swift
import AgentAtom

struct SummaryInput: Encodable, Sendable {
    let article: String
}

struct SummaryOutput: Decodable, Sendable {
    let summary: String
    let sources: [String]?
}

struct Summariser: ModelledSpec {
    typealias Input = SummaryInput
    typealias Output = SummaryOutput

    static let identity = Identity(
        id: "summariser",
        name: "Summariser",
        version: "1.0.0"
    )

    let input: SummaryInput
    var output: SummaryOutput? = nil
    static let role = "You summarise articles."
    let instructions = "Produce a concise, factual summary."
}

let spec = Summariser(input: SummaryInput(article: "Article text"))
let inputText = spec.inputJSON.rawValue
let schemaText = Summariser.outputSchema.rawValue
```

Consumers can decode a response directly or use the typed operation/session API below.
Execution never writes to the spec's optional output property. The caller may retain
the returned output wherever appropriate.

## JSON construction

JSONString's failable string initializer uses Foundation JSONSerialization,
preserves the original text, and accepts JSON objects, arrays, scalars, and null.
Acceptance follows Foundation's parser, which can accept extensions such as
trailing commas on Apple platforms. It is not a separate strict JSON grammar check.
JSONString also supports string literals; an invalid literal is a programming
error and terminates execution.

JSONSchema has a failable model-type initializer. It constructs standard schema
keywords from supported model shapes and uses Foundation to check the serialized
JSON. There is no public schema initializer from raw text or dialect selection.

```swift
let literal: JSONString = #"{"message":"Hello"}"#
let dynamic = JSONString(receivedText) // JSONString?
let schema = JSONSchema(SummaryOutput.self) // JSONSchema?
```

Both types conform to CustomStringConvertible and CustomDebugStringConvertible.
Print and debugger inspection use Foundation's pretty-printed JSON formatting;
rawValue retains the compact provider representation (or original input text).

ModelledSpec uses Foundation JSONEncoder directly, with default strategies,
compact output, and sorted keys. Default getters terminate with preconditionFailure
when conversion or derivation fails. They do not return empty or permissive JSON,
and failure messages do not include input or prompt text. Conformers can replace
either inherited property with their own implementation.

## Schema derivation

The package delegates model inspection to the pinned open-source
[TypeDecoder](https://github.com/Kitura/TypeDecoder) library and maps its type
information into a small Encodable schema representation. Foundation JSONEncoder
serializes it; JSONString checks the emitted JSON syntax. Schema structure is
constructed from known shapes: type, properties, required, items,
additionalProperties, and nullable alternatives. There is no meta-schema engine.

Ordinary model shapes include primitive fields, nested models, CodingKeys, arrays,
string-keyed dictionaries, and optionals. Optional fields can be absent or null;
non-optional fields are required. Generated object schemas permit additional keys,
matching JSONDecoder's ordinary behavior.
Empty structs are supported through a guarded empty-object decoding fallback.

Foundation Date, Data, UUID, URL, and Decimal representations follow JSONDecoder's
default strategies. Derivation does not infer domain validation rules, enum cases,
or integer-width bounds. Unsupported, opaque, and recursive type information fails
construction. Schema conversion is limited to 64 levels; model inspection behavior
is delegated to TypeDecoder.

TypeDecoder probes Decodable initializers using dummy values. Custom decoding can
fail or describe only one execution path, so inferred schemas are not proof of
equivalence to arbitrary custom decoding. Property wrappers and macros would require
model annotations or added metadata; they are not imposed on the Decodable-only API.

This package generates model schemas; it does not validate arbitrary external
schemas or responses. Provider-specific compatibility belongs in adapters.
Provider testing is tracked separately in [#88](https://github.com/Khabarwaani/ScriptMakerServer/issues/88). Adapters must check their provider's
supported keywords and object restrictions, including nullable `anyOf`, formats,
`contentEncoding`, and additional keys, before submitting a generated schema.

## Readability guidance

Use names that explain a type's responsibility and a value's meaning. Keep control
flow explicit, format branches consistently, and scope implementation helpers to
their owning type or file. Group protocol implementations in separate extensions.
Keep comments short; add them for a behavior boundary or useful example rather
than narrating the code. Prefer Foundation APIs over duplicate infrastructure.

Third-party imports are internal; implementation helpers are private or fileprivate.
Access control defines these boundaries without an Internal folder.

## Operations and sessions

`AgenticOperationProtocol` describes a request and its typed decoding.
`AgenticOperation<Specification>` returns the ModelledSpec's Output;
`FailableAgenticOperation<Specification>` returns `AgenticResult<Output>` with
`.success(Output)` or `.failure(AgenticFailure)`. The latter permits the model to
decline a request; both operations can throw execution and decoding errors.

```swift
let session = try AppleIntelligenceSession(configuration: .init(
    instructions: "Be concise and use only supplied facts.",
    supportedOutputTypes: [.json],
    metadata: [.duration, .modelIdentifier, .tokenUsage],
    maximumResponseTokens: 512
))
let operation = AgenticOperation(spec: spec)
let response = try await session.execute(operation)
let output: Summariser.Output = response.content
```

The caller chooses and initializes each session. `AgenticSessionProtocol` has no
configuration requirement; concrete sessions define their own configuration.
There is no singleton. Apple initialization throws on unavailable OS, framework,
device, disabled Apple Intelligence, or unavailable model assets. It also validates
configuration. Availability is rechecked before each generation.

Apple supports macOS/iOS/visionOS 26+ using `SystemLanguageModel.default` locally.
The package itself retains its older deployment minimums. On unsupported platforms
or SDKs, the initializer throws rather than selecting another provider. The adapter
is historyless; each request gets fresh provider instructions and conversation.
History-enabled behavior belongs to a future concrete session specification.

Each Apple session admits one request at a time and throws `.busy` on overlap.
Create separate sessions for concurrency. Cancellation is caller-owned through
Swift Task cancellation, or the stream handle described below. Retries and any
application-wide resource limits also belong to the caller.

### Execution and decoding

`execute(operation)` provides convenience over two independent steps:

```swift
let raw = try await session.respond(to: operation.makeRequest())
let decoded = try operation.decode(raw.content)
```

Both concrete operations accept a custom JSONDecoder through `decode(_:decoder:)`.
The failable decoder validates reserved envelope keys using default strategies,
then applies caller strategies to the nested domain output, with its coding path
starting at that output's root. Unknown outer/failure keys and contradictory or
missing payloads are errors, including an opposite payload set to null. Optional
domain output can be null; failure itself cannot be null.

Successful typed execution guarantees decoding into the declared output type.
It does not validate meaning, truth, list lengths, or other domain rules. Those
checks belong to the caller. The raw `respond` interface is intentionally undecoded.
Provider refusal is a thrown session error; a valid model-authored failable outcome
is a returned result. JSON decoding errors remain decoding errors.

Operations and transport requests are structs with value semantics. Create a fresh
operation per request. The library does not track reuse, deep-copy specs, police
mutation, or add defensive snapshots. Callers must keep reference-backed input and
computed request values stable during execution. Existing ModelledSpec getters
retain their documented conversion preconditions.

### Instruction hierarchy

Instructions are assembled in four levels, highest priority first:

1. Session base instructions.
2. Operation instructions, including package failable guidance.
3. Spec role and instructions.
4. Input content.

The first three levels go into provider instructions. Input is sent separately as
prompt data. String ModelledSpec inputs remain JSON string literals, including
escaping; no input wrapper or unescaping is added. Assembly expresses this priority,
but does not guarantee a model will obey it.

### Streaming

```swift
let stream = try await session.stream(AgenticOperation(spec: spec))
for try await snapshot in stream.snapshots {
    // Replace display content; snapshots are cumulative, not token deltas.
    // Structured partial snapshots are text and may be incomplete JSON.
}
let response = try await stream.result() // Completed typed output and metadata.
```

Starting a stream starts its generation, even before iteration. Snapshots have one
consumer and buffer only the newest element; slower readers can miss intermediate
updates. A snapshot need not extend the previous text as a prefix. `result()` awaits
that same generation and decodes only its completed content. Ending iteration or
seeing valid-looking JSON is not a success signal. Call `cancel()` when abandoning
work, especially after breaking out of iteration while retaining the handle.
Cancelling a result waiter cancels the underlying work; releasing the handle also
requests cancellation. The generation slot is retained until the backend returns.
Buffering bounds snapshot count, not the size of the final response; configure the
provider's response token budget as appropriate.

### Metadata and content capabilities

Metadata is disabled by default. Configuration selects fields to request; disabled
or unavailable fields remain nil. Metadata belongs exclusively to the session
response. Duration measures backend generation with a monotonic clock, excluding
schema translation and domain decoding. `modelIdentifier` identifies the selected
`SystemLanguageModel.default`, not an invented model version. Tier, reasoning effort,
and finish reason remain nil because this adapter cannot determine them reliably.
Token counts use the guarded OS 27 SDK usage API when available; the fresh conversation
contains exactly one request. Older runtimes keep token counts nil. Zero is retained.

The shared content supports text, JSON, and `AgenticImage` (bytes plus media type).
Custom operations conform to AgenticOperationProtocol to decode those content types;
custom sessions conform to AgenticSessionProtocol. They need no Apple imports.
The concrete Apple LLM supports text/JSON output and text/JSON input only. Its
configuration can restrict those outputs but cannot enable image generation.
An image-generation provider is a separate session implementation. Unsupported
output or streaming returns a typed error; default protocol streaming is unsupported.

### Apple schema compatibility

| Schema shape | Guided generation |
| --- | --- |
| String, Boolean, integer, number; root scalars | Translated to Apple primitive schemas; final domain decoding enforces the actual Swift type. |
| Objects and arrays, including roots | Supported. Apple generates only declared object properties, a documented subset of the open domain schema. |
| Optional object property | May be omitted. Its explicit-null alternative is narrowed to omission on the baseline. |
| Required nullable value / nullable array element | Requires OS 26.4+ and an SDK exposing null schemas; otherwise rejected. |
| Tagged success/failure unions | Runtime anyOf with constrained status values and closed package-owned envelopes. |
| Arbitrary-key dictionaries | Rejected. |
| Formats and content encodings (UUID, URL, Data) | Rejected rather than silently dropping constraints. |
| Domain counts, numeric-width rules, custom decoder semantics | Not inferred; final decoding and caller validation apply. |

Guided output uses `GeneratedContent.jsonString`. Unsupported translation throws;
there is no automatic prompt-only fallback, output repair, input truncation, or retry.
Schema construction and compilation are not proof of live generation compatibility.

## Example and feature status

`swift run KeyPointsExample` runs the real local Apple adapter. It requires an
available Apple model and demonstrates normal execution, streaming, and a failable
request. The caller checks exactly three points and prints extracted people.
The example is compiled by `swift build` and is not run automatically.

Implementation: [#87](https://github.com/Khabarwaani/ScriptMakerServer/issues/87).
New automated and live provider testing is a separate task:
[#88](https://github.com/Khabarwaani/ScriptMakerServer/issues/88). Existing Phase 2
tests cover the specification/schema package; they do not verify this adapter.

The feature PR must not merge until the user explicitly authorizes that specific
merge in chat, verified twice. Passing checks or inferred intent are not authorization.

## Build and validation

Run `swift build` and `swift test` from this directory. Swift Testing suites cover public contracts,
ordinary model derivation, the 64-level conversion limit, unsupported models,
Foundation representations, and formatting. On macOS and Linux, a test-only
`FailureProbe` executable checks invalid literals and failing default conversions
in separate processes. No real server or AI provider is started.

The tests use `@testable import AgentAtom`, including Encodable-only inputs and
Decodable-only outputs. Schema assertions check generated keyword structures;
they do not constitute meta-schema validation or prove arbitrary custom decoding.
