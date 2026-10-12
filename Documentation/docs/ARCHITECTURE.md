# Architecture and decisions

The repository keeps Xcode entry points at its root. The executable and reusable
library are the Swift package at `Packages/AgentServer`. Development guidance is in
`Packages/AgentServer/AGENTS.md`; public documentation is in `Documentation`.

## Boundaries

`AgentServer` is the composition root, HTTP contract mapping and SSE transport.
`AgentCore` owns typed configuration, JSON models, semantic versions, registry,
provider contracts/adapters, process lifecycle, actor-owned execution management,
validation and Swift package tooling. It does not import Hummingbird.

`AgentResources` packages default configuration and web pages.
Each agent is an independent SPM library under `Agents/AgentID` conforming to `AgentPackageContract`.
Agent availability requires explicit Swift registration in `AgentRegistry.registeredPackages`.
The build enforces validation of schemas, contracts, resources, and examples, and generates package README
and metadata. At startup, the server verifies packaged validation metadata and rejects unvalidated or changed resources.

## Operational decisions

- Hummingbird 2 and SSE; Swift 6, macOS 14+; loopback only.
- Central JSON settings, default port 8080, 900-second shutdown allowance.
- Kernel-owned per-user/per-port instance locks identify managed previous servers;
  stale PID files cannot accidentally target unrelated processes.
- Startup requests SIGTERM and waits for lock release before replacing a managed server.
- Accepted work drains on graceful shutdown; new work is rejected. Deadline-expired
  work is cancelled and its process is reaped before releasing resources.
- Default process budget is eight, with a bounded burst queue. Provider memory is
  monitored, and process growth pauses at its budget. HTTP connections and active
  provider work are separate; disconnected clients do not cancel executions.
- Bounded event/result buffers and terminal state retention protect memory. Slow or
  disconnected stream consumers detach while their execution continues.
- Exact agent versions are snapshotted and cached as immutable definitions; source
  modifications to a loaded version are ignored until restart. Publish a new version.
- No database, distributed queue, recovery after restart or resumable stream.

## Provider contracts

Adapters handle configured executable resolution, local readiness, input formatting,
stdout/stderr, provider events, final results and scoped termination. They inherit the
normal user environment and cached CLI login. No arbitrary shell command is accepted
through the HTTP API; inputs become JSON prompt data, not shell syntax.

Codex uses read-only exec and native structured output. Antigravity uses sandboxed
headless stream-json and its structured result; known tool transport annotations are
separated without accepting arbitrary extra result fields. Grok uses headless streaming
messages and server-side validation. Provider safeguards remain enabled.

## Validation

The validator implements a documented bounded subset of Draft 2020-12 assertions,
including objects/arrays/strings/numbers, enum/const, local references and compositions.
Unsupported assertions or malformed schemas make definitions unavailable. It is not
a complete implementation of every Draft 2020-12 vocabulary. This explicit rejection
avoids reporting success while silently skipping a constraint.

Only parsed, validated final output emits result and completed. Intermediate provider
text is provisional. Provider failures, malformed JSON and schema mismatches emit
structured failed events. Status records contain operational metadata, not input/prompts.

## Tests and remaining verification

Deterministic Swift tests cover package creation, registry discovery and versions,
immutable snapshots, schema assertions, synthetic Codex/Antigravity/Grok frames,
process I/O, execution success/failure, cancellation, disconnect policy, concurrency,
burst queueing and HTTP contracts. Actual provider login/backend readiness and live
socket behavior need the separate integration run described in RUN.md.

Do not mark every Version 1 acceptance criterion verified merely because mock tests
pass. Live CLI behavior and resource-pressure behavior must be evaluated on the target
Mac with the user's configured providers.

## Platform portability

Core business logic (`ProcessRunner`, `SystemResources`, `ServerInstance`, `CLIProviders`) remains common and platform-agnostic in `Sources/AgentCore`. Low-level operating system hooks are specified by formal protocol contracts (`Protocols/PlatformContracts.swift`) and fulfilled strictly via extensions in dedicated platform directories:
- `Platform/macOS/`: Darwin `F_SETNOSIGPIPE`, Mach `proc_pidinfo` and `host_statistics64`, POSIX process groups, and `fcntl` instance locking.
- `Platform/Linux/`: Glibc, `/proc/<pid>/statm`, `/proc/meminfo`, `SIGPIPE` ignore, and `/proc/<pid>/exe` link inspection.
- `Platform/Windows/`: WinSDK, PSAPI `GetProcessMemoryInfo`, `GlobalMemoryStatusEx`, Win32 Named Mutexes/Events, and `;` PATH delimiter.
