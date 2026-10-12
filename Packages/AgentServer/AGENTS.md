# Development instructions

This repository is the standalone Swift AgentServer package. Read
`../../Documentation/docs/SPECIFICATION.md` and
`../../Documentation/docs/ARCHITECTURE.md` before implementing server behavior.

Follow the agent Git workflow in
[../../Documentation/AGENTS.md](../../Documentation/AGENTS.md): use a worktree
named after the coding agent, a branch based on the bug ID (or a descriptive name
when no ID exists), and pull the latest `develop` before submitting a PR targeting
`develop`. Push only the task branch; direct pushes to `develop` are forbidden.
Squash merge all issue PRs except PRs solely for a version increase, which use a
regular merge preserving commits. Remove the worktree only after the PR merge is
verified on remote `develop` and local `develop` is synced.
Then delete the completed local task branch as described in the linked workflow;
worktree removal alone does not remove the branch. Preserve active branches and
unmerged work, and verify the merged PR head before deleting a squash-merged branch.

- Use Swift 6, Swift Concurrency, Hummingbird 2 and SSE.
- Keep reusable domain code in `AgentCore`; HTTP mapping belongs in `AgentServer`.
- Keep CLI-specific behavior in provider adapters. Never concatenate client data into shell commands.
- Agents are linked Swift subpackages conforming to `AgentPackageContract` and explicitly registered in `AgentRegistry.registeredPackages`.
- Version directories are immutable once published. Change instructions by adding a version and rebuilding.
- Build-time validation validates contracts, resources, schemas and examples; build-generated documentation provides READMEs and help metadata.
- Undeclared or unbuilt agent additions remain unavailable at runtime.
- Preserve loopback defaults; implement authentication before allowing remote binding.
- Never log secrets or full input/prompts by default. Use sanitized structured errors.
- Use deterministic mock providers for unit tests. Live CLI integration tests must be separate and opt-in.
- Run `swift build` and `swift test` for code changes. Keep README implementation status accurate.
- Commit `Package.resolved`; exclude build output, IDE state, local configuration and logs.
- Do not claim Version 1 complete until every acceptance criterion has evidence.

## Required folder structure

Follow Swift Package Manager conventions and group source files by responsibility.
Keep this layout consistent when adding features:

```text
Sources/
  AgentServer/           Executable composition root
    API/                 HTTP routing, request/response mapping and SSE transport
  AgentCore/             Reusable provider-independent library
    Configuration/       Typed settings and configuration loading
    Models/              JSON values, errors, request/event/status models
    Registry/            Definition loading, discovery and semantic versions
    Providers/           CLI adapters, readiness and process I/O
    Execution/           Actor-owned scheduling, tracking, cancellation and cleanup
    Lifecycle/           Single-instance startup and graceful stop
    Validation/          JSON Schema validation
    Tools/               Swift agent-package creation and checking
  AgentResources/        Build-time public config, agent and web asset snapshots
  AgentTools/            Swift command-line developer tool entry point
Tests/
  AgentCoreTests/        Unit and deterministic mock-provider tests
  AgentServerTests/      HTTP contract and transport tests
Agents/
  AgentID/               Independent SPM library package
    Package.swift
    README.md
    Sources/AgentID/      Swift definition access
    Tests/AgentIDTests/   Resource checks
    1.0.0/               Immutable runtime Markdown and schema definition
config/server.json       Central server configuration
../../Documentation/     Specification, architecture and run instructions
../../ignoreGit/         Ignored local-only helpers; never committed
```

- Put behavior in the owning feature folder; avoid miscellaneous catch-all files.
- Keep entry points small. Core code must not import Hummingbird or contain route logic.
- Use Swift for application code, package tooling and automated tests. Do not add Python helpers.
- Runtime agent version directories follow the documented registry contract; they are not compiled modules.
- Each agent package must include its manifest, Swift source, tests, README, role, instructions and output schema.
- Keep local Git/authentication setup scripts out of tracked source. Store any such helpers in `ignoreGit/`.
- Serve config, agent definitions and web resources from build output. Provider working directories belong in Application Support, not the source checkout.
