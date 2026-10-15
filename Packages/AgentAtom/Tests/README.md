# AgentAtom validation

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
and configuration bounds. Only the instruction-failure/schema tests use
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
A separate failable live test checks `generationFailed(reason:)` for insufficient
input, and a streaming live test decodes only the final snapshot. No output repair,
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
| Deterministic suite | 42 enabled tests passed; four opt-in live tests skipped |
| Apple readiness and failable init | Passed; model reported available |
| Named and no-person live samples | Failed direct JSON decoding: output began with a backtick |
| Failable insufficient-input sample | Failed: returned a schema object, then a one-point success after prompt refinement |
| Live streaming sample | Failed direct final JSON decoding: output began with a backtick |
| iOS simulator target, deployment 16 | AgentAtom library build passed with SDK 27 |
| tvOS simulator target, deployment 16 | AgentAtom library build passed with Apple provider excluded, SDK 27 |

The live failures reproduced after stronger sample instructions and remain tracked
in [#91](https://github.com/Khabarwaani/ScriptMakerServer/issues/91). Live tests stay
opt-in and retain their failing assertions. Fixture success is not evidence of live
schema adherence. No production architecture changes are included in this test task.

Older compilers, Linux, other deployment targets, device runs, and live cancellation
latency have not been verified. No code coverage percentage is claimed. Apple's
private admission/recording implementation is not replaced by an injected backend;
the deterministic concurrent-session checks exercise the fixture contract.
