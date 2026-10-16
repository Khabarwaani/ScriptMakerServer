# AgentAtom validation

These commands apply to the retained ScriptMakerServer snapshot. For the public
**0.0.1** package, clone [abhi266raj/AgentAtom](https://github.com/abhi266raj/AgentAtom)
and run `swift test` at its root. Its [test guide](https://github.com/abhi266raj/AgentAtom/blob/0.0.1/Tests/README.md)
and [macOS example](https://github.com/abhi266raj/AgentAtom/tree/0.0.1/Examples/AgentAtomDemo)
are standalone. The dependency migration is a separate task; see
[publication notes](../../../Documentation/docs/AGENTATOM_PUBLICATION.md).
Run deterministic tests from the repository root:

```sh
swift test --package-path Packages/AgentAtom
```

The fixture session is test-only. Its synchronization gates control admission,
provider completion, and late pause/resume responses without timing-based delays.
These tests validate operations against a session contract; they do not prove that
the Apple provider follows a schema or shares the fixture's implementation.

Coverage includes all four operation result modes, plain Spec and ModelledSpec,
raw response preservation, reserved failure parsing, schema derivation, reuse,
identity, overlapping calls, concurrent metadata reads, cancellation cleanup,
stream termination and reference release, lifecycle capabilities, stale responses,
and configuration bounds. Only instruction-failure/schema and native adapter tests use
`@testable`; normal operation tests consume the public API.

## KeyPoints sample

[KeyPointsSpec](AgentAtomTests/Support/KeyPointsSpec.swift) implements the sample
from issue #80 with `Input = String`, a Decodable/Sendable output containing
`points` and `person`, and caller-owned optional output storage. It requires three
supported points and distinct explicit names in first-appearance order. Fixtures
cover named-person and no-person prose; the live suite uses the actual Apple session.

```swift
let spec = KeyPointsSpec(input: KeyPointsSpec.namedInput)
let operation = AgenticOperation(spec: spec, session: session)
let json = try await operation.execute().get()
let output = try JSONDecoder().decode(KeyPointsOutput.self, from: Data(json.utf8))
guard output.points.count == 3 else {
    throw AgenticError.operationFailed(reason: "Expected exactly three key points.")
}
```

The caller decodes and validates output; operations never write `spec.output`.
Both failable modes check success for sufficient input and `generationFailed(reason:)`
for a greeting and two-fact input. Streaming tests decode only the final snapshot.
Three points is this caller-owned sample requirement, never an AgentAtom rule. No output repair,
fence stripping, fake live results, or additional executable product is used.

## Opt-in Apple validation

```sh
AGENTATOM_LIVE_TESTS=1 swift test --package-path Packages/AgentAtom --filter AppleKeyPointsTests
```

Live tests require macOS/iOS/visionOS 26+ and an available local Apple model. Model
checks are skipped when unavailable; a separate test reports availability and checks
the failable initializer. Regular tests do not invoke a model or network service.

Observed on macOS 27.0.1, Xcode 27.0, Apple Swift 6.4:

| Check | Observed result |
| --- | --- |
| Deterministic suite | 48 enabled test functions passed; six opt-in live functions skipped by default |
| Apple readiness and failable init | Passed; model reported available |
| Named and no-person live samples | Passed direct JSON decoding, three points and expected names |
| Both failable modes | Sufficient input succeeded; greeting and two-fact input returned AI-declared failures |
| Live streaming sample | Passed direct final JSON decoding and expected points/names |
| Unsupported Apple schema | Failed before admission with diagnostic error and no execution record, as expected |
| iOS simulator target, deployment 16 | AgentAtom library build passed with SDK 27 |
| tvOS simulator target, deployment 16 | AgentAtom library build passed with Apple provider excluded, SDK 27 |

The full live run enables all 54 test functions; parameterized cases are additional.
The original prompt-only adapter produced fenced JSON and invalid partial successes
([#91](https://github.com/Khabarwaani/ScriptMakerServer/issues/91)). The fix uses native
schema-based generation and `GeneratedContent.jsonString`, including a reserved
failure alternative. Native schema tests cover object ordering, required properties,
nullable/nested shapes, fixed failure discriminators, and unsupported constraints.
The sample instructions clarify feasibility with examples. No fixed count, output
repair, second model request, or caller-output decoding is added to AgentAtom.
These observed model successes do not establish universal semantic compliance.

Older compilers, Linux, other deployment targets, device runs, and live cancellation
latency have not been verified. No code coverage percentage is claimed. Apple's
private admission/recording implementation is not replaced by an injected backend;
the deterministic concurrent-session checks exercise the fixture contract.
