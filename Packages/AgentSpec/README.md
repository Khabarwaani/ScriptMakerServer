# AgentSpec

A standalone Swift package for provider-independent agent specifications. Copy this
directory into a separate repository without changing its source or dependency
paths. It has no dependency on AgentServer or the other packages in this repository.

## Requirements

Swift 6.1 or later, using Swift 6 language mode. The schema validator dependency
requires Swift 6.1. Supported Apple deployment targets are declared in Package.swift;
the package also uses cross-platform Foundation APIs.

## Public contract

`Spec` exposes static `Identity` (id, name, version), instance role and instructions,
validated input JSON, and a validated output schema. Both JSON properties are
non-optional and non-throwing.

`ModelledSpec<Input, Output>` adds an `Encodable & Sendable` input and a
`Decodable & Sendable` output. It supplies both JSON properties by default. Output
models need no schema protocol, sample instance, or Encodable conformance.

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
    let role = "You summarise articles."
    let instructions = "Produce a concise, factual summary."
}

let spec = Summariser(input: SummaryInput(article: "Article text"))
let inputText = spec.inputJSON.rawValue
let schemaText = spec.outputSchema.rawValue
```

There is no provider execution or response-decoding method in the protocol. A
consumer can decode its received response into `Summariser.Output` using JSONDecoder.

## Validated values

`JSONString` accepts objects, arrays, strings, numbers, booleans, and null. Its
throwing initializer preserves the original text. Its encoding initializer uses
JSONEncoder's default strategies, compact output, and sorted keys.

```swift
let literal: JSONString = #"{"message":"Hello"}"#
let dynamic = try JSONString(receivedText)
let encoded = try JSONString(encoding: SummaryInput(article: "Article text"))

let explicit = try JSONSchema(
    #"{"type":"object","properties":{"summary":{"type":"string"}},"required":["summary"]}"#
)
let derived = try JSONSchema(SummaryOutput.self)
```

An invalid JSON literal terminates with preconditionFailure. Throwing initializers
are available for dynamic text and recoverable encoding/derivation failures.
Default ModelledSpec getters also terminate on conversion failure, because the
contract permits neither an error nor an absent value. Their failure messages do
not include input or prompt text.

## Output schemas

JSONSchema validates against the Draft 2020-12 meta-schema using the pinned
swift-json-schema validator. Its bundled meta-schema resources are loaded locally;
validation performs no network requests. An absent root `$schema` means Draft
2020-12; other explicit root dialects are rejected. Valid JSON syntax alone is
insufficient. Public validation errors describe schema paths and keywords without
exposing dependency types.

Schema validity does not imply compatibility with every AI provider. Keep provider
adaptation outside this package. Schema validation also does not validate an agent
response against that schema.

Type-based initialization observes decoding through an internal Decoder. Supported
ordinary synthesized models include:

- String, Bool, integer types, Float, and Double.
- Nested models and custom CodingKeys.
- Arrays and string-keyed dictionaries.
- Optional values, represented as nullable schemas; optional keyed fields may also
  be absent, while non-optional fields are required.
- Foundation Date (numeric seconds since the reference date), Data (base64 string),
  UUID, URL, and Decimal, matching JSONDecoder's default representations.

Generated object schemas permit additional keys, matching JSONDecoder's ordinary
behavior. Generated schemas describe JSON structure; they do not express Swift
integer-width bounds or infer domain constraints such as ranges and descriptions.

Enums, recursive models, non-string dictionary keys, custom containers, inherited
decoding, and detectable conditional decoding require an explicit schema. Derivation
is bounded to 64 levels and 1,024 model visits.

Decodable exposes executable decoding behavior, not complete type metadata. Arbitrary
custom decoding can impose value-dependent rules that cannot be inferred exactly;
use an explicit schema for such models even if a probe succeeds. Inferred schema
validity is not proof of exact equivalence to custom decoding semantics.

Implement either inherited property to replace its default. For example, an agent
with a custom-decoded output can supply a validated schema without changing its model:

```swift
// Inside a ModelledSpec conformance:
var outputSchema: JSONSchema {
    do {
        return try JSONSchema(#"{"type":"string","enum":["accepted","rejected"]}"#)
    } catch {
        preconditionFailure("Invalid declared output schema")
    }
}
```

## Build and phases

Run `swift build` from this directory. Phase 1 contains the library implementation
and documentation only. Tests and broader conformance verification are tracked in
[Phase 2, issue #76](https://github.com/Khabarwaani/ScriptMakerServer/issues/76).

The validator is imported internally. Parsing, derivation, resources, and dependency
diagnostics are not part of the public API.
