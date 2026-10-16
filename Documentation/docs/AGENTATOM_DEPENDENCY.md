# AgentAtom dependency

Canonical source, releases and internal tests: https://github.com/abhi266raj/AgentAtom.
NewsAgent and TerminalAgentSession depend on exact **0.1.0**, binary product
`AgentAtom`, retaining `import AgentAtom`. Generic framework changes belong
upstream. Domain specs and CLI adapters remain here. The source variant
`AgentAtomSource` has a separate module identity; never mix variants in one graph.

Semantic tag `0.1.0` pins revision `df95fa03457ab53b72bbdce951ff6839632f53dc`.
Its release manifest downloads `AgentAtom.xcframework.zip` from the immutable
`artifacts-0.1.0` release with SHA-256:

```text
4664c6a1726478a8dbe1e202699a14b40b3d5a9904445118860aa4f6842776f4
```

SwiftPM checks the archive automatically. Clean checkouts need network access,
no sibling checkout or local XCFramework build. The upstream development manifest
expects a local artifact and must not replace the semantic-version dependency.
Commit affected SwiftPM and Xcode lockfiles without unrelated upgrades.

## Platforms and runtime packaging

The release contains universal macOS, iOS device and iOS simulator slices.
NewsAgent declares macOS 14+ and iOS 16+; TerminalAgentSession requires macOS 15+.
The previous tvOS/watchOS/visionOS NewsAgent declarations are removed because this
binary release supplies no matching slices. Use a toolchain compatible with the
release's Swift module interfaces (validated here with Xcode 27 / Swift 6.4).

`swift build`, `swift test` and the Xcode workspace resolve the binary product.
Command-line executables include `@executable_path` in their runtime search paths.
SwiftPM/Xcode stage the framework in their build products. For deployment, copy
`AgentAtom.framework` beside AgentServer, AgentTools and AgentValidator, retaining
its symlinks, and include the license/dependency notices. The embedding helper
makes this explicit for SwiftPM build products:

```sh
swift build --package-path Packages/AgentServer
Development/embed-agentatom.sh Packages/AgentServer debug
```

Run the helper with `release` after a release build. Applications embedding the
unsigned framework must sign it as part of their own distribution. See the
[upstream distribution guide](https://github.com/abhi266raj/AgentAtom/blob/0.1.0/Distribution/README.md).

## Validation and ownership

```sh
swift test --package-path Packages/NewsAgent
swift test --package-path Packages/TerminalAgentSession
swift test --package-path Packages/AgentServer
swift test --package-path Packages/AgentServer/Agents/ShekharJokeGenerator
swift run --package-path Packages/AgentServer AgentTools docs --check
xcodebuild -workspace AgentServer.xcworkspace -scheme AgentServer \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

These suites test domain contracts, terminal adapters (including Antigravity), and
server behavior against the public binary. Framework-internal tests run upstream;
there is no duplicate framework source/test tree here. This migration preserves
the server's provider integration and global generation/feasibility guidance.
Real server smoke checks use `AGENT_SERVER_ENV=testing`, read the automatically
selected address from startup, and terminate only the process they start.

## Licensing

AgentAtom remains **AGPL-3.0-only**, including binary distribution. Public source:
https://github.com/abhi266raj/AgentAtom/tree/0.1.0. Preserve the
[license, copyright and third-party notices](../ThirdParty/AgentAtom/THIRD_PARTY_NOTICES.md)
when redistributing. TypeDecoder 2.0.0 is statically linked into the binary and
retains its Apache-2.0 license. The XCFramework archive also contains these notices.
