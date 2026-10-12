# Development instructions

This repository is the standalone Swift AgentServer package. Read
`docs/SPECIFICATION.md` and `docs/ARCHITECTURE.md` before implementing server behavior.

- Use Swift 6, Swift Concurrency, Hummingbird 2 and SSE.
- Keep reusable domain code in `AgentCore`; HTTP mapping belongs in `AgentServer`.
- Keep CLI-specific behavior in provider adapters. Never concatenate client data into shell commands.
- Agent directories are runtime configuration, not automatically compiled SPM targets.
- Version directories are immutable once published. Change instructions by adding a version.
- Preserve loopback defaults; implement authentication before allowing remote binding.
- Never log secrets or full input/prompts by default. Use sanitized structured errors.
- Use deterministic mock providers for unit tests. Live CLI integration tests must be separate and opt-in.
- Run `swift build` and `swift test` for code changes. Keep README implementation status accurate.
- Commit `Package.resolved`; exclude build output, IDE state, local configuration and logs.
- Do not claim Version 1 complete until every acceptance criterion has evidence.
