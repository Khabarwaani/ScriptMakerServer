# AgentSpec

A standalone Swift package for provider-independent agent specifications. This
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
import AgentSpec

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

Consumers can decode the response into `Summariser.Output` using Foundation's
JSONDecoder and assign it to a mutable spec's output property. The package does not
execute providers or add a decoding method to Spec.

## JSON construction

JSONString's failable string initializer uses Foundation JSONSerialization,
preserves the original text, and accepts JSON objects, arrays, scalars, and null.
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

## Build and phases

Run `swift build` from this directory. Phase 1 contains implementation and
documentation only. Automated tests and broader conformance verification are
tracked in [Phase 2, issue #76](https://github.com/Khabarwaani/ScriptMakerServer/issues/76).

Third-party imports are internal; implementation helpers are private or fileprivate.
Access control defines these boundaries without an Internal folder.
