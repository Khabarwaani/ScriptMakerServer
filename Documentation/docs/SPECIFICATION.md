# AI Agent Server

Requirements Specification — Version 1.0

This document records the supplied Version 1 requirements. Framework and protocol
decisions are recorded in [ARCHITECTURE.md](ARCHITECTURE.md). Implementation progress
is recorded separately; this specification does not imply that the bootstrap
already satisfies these requirements.

## 1. Purpose

Build a lightweight, persistent AI agent server in Swift exposing a common
interface for discovering, executing, monitoring and cancelling AI agents.
The server must be independent of AI providers and support command-line tools
such as Codex and Antigravity through provider adapters. Agents must be
independently defined, versioned, discoverable and reusable by applications and
Swift packages. Initially expose four HTTP endpoints.

## 2. Design principles

1. Provider independence: agent definitions must not depend on a provider.
2. Versioned agents: multiple versions of an agent must coexist.
3. Package-backed discovery: only explicitly linked and registered versions are available after a rebuild.
4. Structured input/output: requests use JSON; successful final results conform to the selected output schema.
5. Optional status streaming: deliver lifecycle/progress events when requested; keep provider output internal.
6. Asynchronous execution: execute multiple agents concurrently.
7. Simplicity: avoid databases, brokers, distributed workers and unnecessary infrastructure.
8. Reproducibility: record the exact agent version and provider for every execution.

## 3. Technology

| Area | Requirement / selected technology |
| --- | --- |
| Language | Swift |
| HTTP framework | Hummingbird (selected before development; Vapor was an alternative) |
| Concurrency | Swift Concurrency and asynchronous I/O |
| Input/output | JSON |
| Agent instructions | Markdown |
| Output validation | JSON Schema |
| Responses | Final JSON by default; optional `status=true` SSE for lifecycle/progress and the validated result |
| AI execution | Provider-specific CLI adapters |
| Dependencies | Swift Package Manager (SPM) |

## 4. Agent definition

Each agent has a unique identifier and one or more immutable semantic versions.
Each version consists of four conceptual components:

### 4.1 Role

`role.md` contains a complete natural-language sentence describing responsibility.
Example:

> You are a news researcher responsible for gathering reliable information, verifying factual claims, and producing structured research findings.

### 4.2 Instructions

`instructions.md` contains detailed rules, workflow and constraints. Instructions
may be split across multiple Markdown files with an explicitly defined load order.

### 4.3 Input

The client supplies a JSON object per execution. Structures may differ by agent;
the server passes input without assuming domain-specific fields. An optional
agent-specific input schema may be used for validation.

### 4.4 Output schema

`output.schema.json` defines required final-result structure and constraints.
The server validates the final result before reporting successful completion.

## 5. Agent storage and discovery

The initial implementation supports directory-based definitions:

```text
AgentServer/
├── Package.swift
├── Sources/
├── Tests/
└── Agents/
    ├── NewsResearcher/
    │   ├── 1.0.0/
    │   │   ├── role.md
    │   │   ├── instructions.md
    │   │   └── output.schema.json
    │   └── 1.1.0/
    │       ├── role.md
    │       ├── instructions.md
    │       └── output.schema.json
    ScriptRefiner/
        └── 1.0.0/
            ├── role.md
            ├── instructions.md
            ├── input.schema.json
            └── output.schema.json
```

The registry discovers explicitly registered Swift agent packages and their declared
versions. Build-time validation checks contracts, schemas, examples and resources;
startup verifies validation metadata. Invalid or undeclared definitions remain
unavailable. Definitions are cached as immutable snapshots and do not change during
execution. Adding or changing versions requires package declarations and a rebuild.
The configurable storage root supports validation and tooling; it does not make
undeclared Markdown directories available at runtime.

### 5.1 Version resolution

- An explicit version selects that exact version.
- Without a version, select the highest available stable semantic version.
- Never automatically select a prerelease.
- Unknown agents or versions produce structured errors.
- Once execution begins, the resolved version remains fixed.
- Version identifiers must follow semantic versioning.

## 6. HTTP API

### 6.1 List agents — `GET /agents`

Return only valid registered agent IDs, display names and all available versions.
Full contracts, documentation and provider metadata are available from `/openapi.json`.
Do not expose private configuration, credentials or environment variables.

```json
{
  "agents": [
    {"id": "NewsResearcher", "name": "News Researcher", "versions": ["1.1.0"]},
    {"id": "ScriptRefiner", "name": "Script Refiner", "versions": ["1.0.0"]}
  ]
}
```

### 6.2 Execute agent — `POST /execute`

Execute an agent and return one final schema-validated JSON value, or a structured
error, by default. The optional query parameter `status` defaults to `false`; omit
it or pass `status=false` for final-only mode. Pass `status=true` to opt into SSE
status/progress updates and one validated final result or terminal error. Raw
provider output is internal and is not returned in either response mode.

Version is optional; omission selects latest
stable. Validate provider selection and readiness before execution begins.

```json
{
  "agent_id": "NewsResearcher",
  "version": "1.1.0",
  "provider": "codex",
  "input": {"topic": "India's semiconductor industry", "language": "English"}
}
```

Execution sequence:

1. Validate the request.
2. Resolve agent ID and version.
3. Load role, instructions and output schema.
4. Resolve and initialize the provider.
5. Construct its provider-specific execution request.
6. Deliver agent instructions and JSON input.
7. Process provider output internally; stream only lifecycle/progress when `status=true`.
8. Obtain and parse final JSON.
9. Validate the result against the output schema.
10. Emit successful completion only after validation succeeds.

Adapters handle differing input formats, structured-output features and streaming
capabilities. Define events for started, status/progress, incremental output when
available internally, final validated result, successful completion, failure and cancellation.
Final results must be distinguishable from intermediate output. Invalid JSON or
schema failure must never produce successful completion. After streaming begins,
emit a structured error event when possible and close the stream appropriately.

Default responses use `application/json` and contain the final JSON directly,
without a result envelope. Failures use the standard error envelope and an appropriate
HTTP error status. `Accept: text/event-stream` alone does not enable streaming.

Only `POST /execute?status=true` uses the following SSE format
(JSON `data` with ordered event names):

```text
event: started
data: {"execution_id":"exec_001","agent_id":"NewsResearcher","version":"1.1.0","provider":"codex"}

event: status
data: {"execution_id":"exec_001","status":"running"}

event: result
data: {"execution_id":"exec_001","result":{"status":"pass","confidence":95,"key_notes":["Research complete"]}}

event: completed
data: {"execution_id":"exec_001"}

```

Additional events are `status`, `failed` and `cancelled`. Result payloads depend
on the selected schema; this example is illustrative.

### 6.3 Server/execution status — `GET /status`

Return a snapshot of health and tracked executions, not an output stream.

```json
{
  "status": "healthy",
  "server": {"version": "1.0.0", "uptime_seconds": 3600},
  "active_executions": 1,
  "executions": [
    {
      "execution_id": "exec_001",
      "agent_id": "NewsResearcher",
      "version": "1.1.0",
      "provider": "codex",
      "status": "running",
      "streaming": true,
      "started_at": "2026-10-12T06:00:00Z",
      "running_at": "2026-10-12T06:00:02Z",
      "elapsed_seconds": 30.5
    }
  ]
}
```

Report overall health, tracked states, ID, agent ID, resolved version, provider,
start time and whether output is actively streaming. Distinguish running,
completed, failed, cancelling and cancelled; queued work may use an additional
`queued` state. Include relevant aggregates such as active execution count.
Timing uses ISO 8601 timestamps: `started_at` is acceptance time, `running_at` is
when execution begins running, and `elapsed_seconds` excludes queue time and freezes
at `ended_at` on termination. Queued work has zero running duration. SSE events also
include timing metadata. Terminal records retain only ID, state and timing; active
records include agent/provider and operational metadata. Tracking is in memory for
the current server session and is purged after shutdown drains or cancels work.
Do not expose prompts, credentials or environment variables.

Assign an execution ID when accepted. In final-only mode, the `X-Execution-ID` header
arrives with the final response; clients can inspect `/status` while waiting. In status
mode it arrives with the started event. The client must be able to obtain it even
if disconnected from the response: return it in `X-Execution-ID`, in the started
event and in status records. Retain state long enough for monitoring and cleanup
without requiring permanent storage.

### 6.4 Cancel — `POST /executions/{execution_id}/cancel`

```json
{"execution_id": "exec_001", "status": "cancelling"}
```

1. Verify existence; return a structured error for unknown IDs.
2. Request cancellation of that execution.
3. Stop its AI process through the provider's termination mechanism.
4. Close its associated output stream.
5. Release resources after termination.
6. Mark cancelled once termination is confirmed.
7. Handle repeated requests safely.

Cancellation must not terminate unrelated processes or affect other executions.
Continue tracking a provider that does not stop immediately until termination
is confirmed or a terminal error is recorded. Cancellation is best-effort because
external providers may not support immediate termination.

## 7. Provider adapter architecture

Providers are separate from definitions. Define a common internal provider
interface and an adapter for each supported CLI. Suggested components:

```text
API/         AgentRoutes, ExecuteRoutes, StatusRoutes
Registry/    AgentRegistry, AgentLoader, VersionResolver
Providers/   AIProvider, CodexProvider, AntigravityProvider
Execution/   ExecutionManager, ExecutionRecord, StreamManager
Validation/  OutputValidator
```

The source layout may change. Adapters handle availability and initialization,
provider-specific formatting, process creation/lifecycle, stdout/stderr, streaming,
error translation, cancellation/termination and structured-output capabilities.
The central workflow must not scatter provider-specific logic throughout core
code. Installation alone does not prove readiness: check authentication and
required configuration during setup and runtime.

## 8. Execution management and concurrency

Support concurrent executions. Normal workload is approximately four to five
AI processes; this is a target, not a hard cap.

- Permit more than five when system resources allow; never reject solely because five are running.
- Monitor process/system resource usage and avoid uncontrolled subprocess creation during bursts.
- Apply backpressure or defer work when needed for stability.
- Keep input, instructions, process, output and state independent per execution.
- Cancel only the requested execution.
- Clean up terminated processes and release resources.

Use a simple in-process manager; no distributed queue is required. Distinguish
HTTP connections from active AI processes: many clients may connect while few
AI executions run.

## 9. Streaming and connection lifecycle

- Deliver incremental output from capable providers without buffering the entire response first.
- Preserve event ordering per execution.
- Handle disconnects without resource leaks.
- Define disconnect behavior; do not silently treat disconnect as cancellation unless explicitly configured.
- Cancellation closes the associated stream.
- Emit terminal events while the connection remains available.
- Account for provider-side buffering.

The selected initial policy is to continue executions after client disconnect,
detach stream resources and retain status. Separate stream-close/reconnect
endpoints, resumable streams and persistent recovery are outside scope.

## 10. Swift Package Manager

Each agent is an independently linked Swift package conforming to
`AgentPackageContract`, with versioned Markdown/schema resources and explicit
registration in `AgentRegistry.registeredPackages`. New agent directories are not
compiled or registered automatically. Update dependencies, declared resource versions
and registration, then rebuild the server to make changes available.

The build validates declarations, schemas and examples and embeds documentation
metadata for help. Checked-in agent READMEs are generated from the same resources:
refresh with `AgentTools docs`, commit them, and verify with `AgentTools docs --check`
before PRs and releases. Builds do not mutate source README files. Version identifiers
remain immutable and independently addressable; multiple versions of a package
identity are not dynamically linked at runtime.

## 11. Error handling

Return consistent structured errors with stable code, readable message and
execution ID when assigned. Minimum cases:

- Invalid request JSON or missing required fields.
- Unknown agent ID or version.
- Invalid/incomplete definition.
- Unsupported/unavailable provider or initialization failure.
- Process launch failure, timeout or provider execution failure.
- Invalid final JSON or output schema validation failure.
- Unknown execution ID or cancellation failure.
- Internal server errors.

Never expose credentials, environment variables or private provider configuration.
Recommended common envelope, including inside streamed `failed` events:

```json
{"error":{"code":"output_schema_validation_failed","message":"The final result does not match the agent output schema.","execution_id":"exec_001"}}
```

Before streaming, use appropriate HTTP error status; after streaming begins,
use the error event rather than attempting to replace the HTTP response status.

## 12. Security and local operation

Initial target: local macOS server. Bind loopback by default. Remote access must
be explicitly configured and authenticated. Do not expose arbitrary shell
execution. Execute only configured supported providers. Validate identifiers and
paths against traversal, including resolved paths and symlink escapes. Treat
instructions as trusted configuration, never authorization to bypass safeguards.
Avoid logging secrets or unnecessary sensitive input. Execute configured
instructions through approved providers rather than treating input as shell commands.

## 13. Observability

Record execution ID, agent ID/resolved version, provider, start/end times, outcome,
cancellation outcome, schema validation outcome and relevant process errors.
Detailed logs must not unnecessarily duplicate prompts, sensitive input or
credentials. `/status` exposes operational state without confidential data.

## 14. Testing requirements

Use deterministic mock providers; not every unit test may require live provider
calls. Provide a separate integration path for real CLI execution.

| Area | Required automated coverage |
| --- | --- |
| Registry | Multiple agents/versions, explicit version, latest stable, unknown version, invalid definitions |
| Execution | Success, JSON input delivery, incremental output, final validation, provider failure, concurrent isolation |
| Status/cancellation | Running and terminal states, cancelling one without affecting another, stream closure, repeated cancellation, cleanup after success/failure/cancellation |
| Server | Endpoint validation, structured errors, disconnects, resource cleanup, four-to-five concurrent executions and extra burst requests |

## 15. Out of scope for Version 1

No database, distributed queue, multiple instances, web administration dashboard,
user accounts/multi-tenant authorization, recovery of running executions after
restart, resumable streams, arbitrary executable plugins, automatic compilation
of new agent packages or hard five-process concurrency cap. Revisit only if
actual requirements justify them.

## 16. Acceptance criteria

Version 1 is complete when:

1. The server starts and remains available as a persistent local service.
2. `/agents` lists valid agents and available versions.
3. `/execute` resolves exact versions or latest stable on omission.
4. The selected agent executes through the selected provider.
5. Clients receive incremental events and a validated final JSON result.
6. `/status` reports health and all tracked execution states.
7. Cancellation targets one execution and closes its stream.
8. Multiple versions execute independently.
9. Concurrent executions never mix inputs, output or cancellation state.
10. Expected workload is handled without avoidable blocking or resource leaks.
11. Newly declared, registered versions become available after a rebuild; undeclared additions remain unavailable.
12. Provider failures, invalid output and cancellation failures are clear.

Final architectural objective: a small, reliable Swift service providing a common
execution layer for versioned agents while keeping definitions, providers and
client applications independent.
