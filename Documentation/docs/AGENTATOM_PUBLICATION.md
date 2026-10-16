# AgentAtom publication and migration

Canonical repository: https://github.com/abhi266raj/AgentAtom

Initial standalone release: [**0.0.1**](https://github.com/abhi266raj/AgentAtom/releases/tag/0.0.1) (matching Git tag), commit `738fae34035799dc2651af647dc32be2f0e34f85`. The public repository
starts with a clean package-only commit, uses GNU AGPL v3 only, and includes the
library, its tests, standalone documentation, dependency notices, and a runnable
SwiftUI macOS example. Its `master` branch is locked; outside users cannot directly
update it. Forks and compliant modification/redistribution remain allowed by AGPL.

## Current state

`Packages/AgentAtom` remains the local ScriptMakerServer snapshot. NewsAgent still
uses `.package(path: "../AgentAtom")`. No manifest or lockfile is changed by the
publication task. Local package tests still run with:

```sh
swift test --package-path Packages/AgentAtom
```

For the standalone release, clone its public repository and use `swift build`
and `swift test` from its root. Follow its README for SwiftPM installation at
exact version `0.0.1`; its example-app README supplies the Xcode build command.

## Maintenance and next task

Future AgentAtom development belongs in the public repository. Synchronize this
local snapshot only through an explicit reviewed change while it remains in use.
The follow-up migration must:

1. Switch NewsAgent to the canonical remote URL and exact version `0.0.1`.
2. Resolve affected SwiftPM/Xcode lockfiles; avoid unrelated dependency updates.
3. Build/test NewsAgent, AgentServer, and affected Xcode entry points against the
   remote package from a clean checkout.
4. Remove the duplicate local package only after all consumers use the release.
5. Update all affected documentation and address AGPL obligations for distribution
   of consuming applications or network services.

The verified release is tracked by [migration task #110](https://github.com/Khabarwaani/ScriptMakerServer/issues/110). The publication change does not perform that later dependency migration.

The standalone release's sample/test specifications request actionable rejection reasons, and the sample displays full AI-declared/provider error details. That presentation guidance changes only tests and the sample, not AgentAtom library behavior. The local snapshot is intentionally unchanged until the migration.
