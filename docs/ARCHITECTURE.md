# Architecture and implementation plan

## Decisions made before development

- HTTP: Hummingbird 2, managed by SwiftPM.
- Streaming: Server-Sent Events (`text/event-stream`), with JSON event payloads.
- Platform: macOS 14+, Swift 6, loopback by default.
- Agent storage: configurable filesystem root, runtime discovery independent of SPM.
- State: in-memory actor-owned registry and execution records; no database or broker.
- Schema target: JSON Schema Draft 2020-12. Select a validator with verified keyword
  support and reject unsupported schemas rather than silently ignoring constraints.
- Disconnect policy: continue execution by default, detach the writer, and retain
  terminal status. An explicit future option may cancel on disconnect.

## Boundaries

`AgentCore` will hold registry/loading, semantic version resolution, provider
contracts, execution management and schema validation. `AgentServer` owns HTTP
request validation, route mapping, SSE encoding and sanitized error responses.

A provider contract must expose readiness checking, execution events, final JSON
and cancellation with confirmed termination. Codex and Antigravity adapters must
be implemented against verified CLI behavior. No adapter currently exists; installed
executables must not be reported as authenticated or ready without a readiness check.

## Execution and streaming

Resolve and snapshot an immutable definition before accepting work. Assign an
execution ID, send `X-Execution-ID` in response headers, include it in every SSE
payload and expose the record through `/status`. Status discovery remains available
if the client loses the streaming response before receiving the header or event.
There is no recovery across server restarts or reconnect endpoint in Version 1.

Use ordered SSE event names: `started`, `status`, `output`, `result`, `completed`,
`failed`, `cancelled`. Only a parsed, schema-valid final value produces `result`
followed by `completed`. A failure produces `failed` and closes the stream;
confirmed cancellation produces `cancelled` and closes it. Intermediate output
must never be confused with final JSON. Use bounded buffering and detach a slow
or disconnected HTTP writer without silently cancelling execution.

The manager should use an actor for transitions and isolated tasks for providers.
Track pending work separately from active processes and HTTP connections. Resource
pressure can defer work into a bounded queue; an operational resource budget must
allow more than five processes and must not impose a fixed five-process cap.
Cancellation must cover queued and running work, remain idempotent, terminate only
the execution's process, and escalate within an adapter if graceful termination fails.
Do not mark cancellation confirmed while a subprocess is still alive.

Retain terminal metadata for a documented configurable interval and bound the
number of retained records. Reap process resources immediately at termination;
retaining status does not retain pipes, subprocesses or prompt payloads.

## Implementation milestones

1. Bootstrap: package, Xcode project/workspace, documentation, example agent,
   configuration, health route, browser input form and API help.
2. Registry: strict SemVer, safe paths, complete definition checks, immutable cache,
   runtime refresh, latest stable resolution and `GET /agents`.
3. Execution: JSON request model, provider protocol, mock provider, manager and
   schema validator. Implement sanitized structured errors and SSE.
4. Lifecycle: tracking, timeout, queued work, process resource monitoring, disconnects,
   scoped cancellation, terminal retention and cleanup.
5. CLI adapters: verified Codex and Antigravity readiness, formatting, incremental
   output, structured output, process lifetime and cancellation.
6. Acceptance: endpoint and mock-provider coverage, four/five concurrent executions,
   burst requests and opt-in CLI integration checks.

Only milestone 1 is included in the initial package. The specification's Version
1.0 describes the intended product; the bootstrap executable version is 0.1.0.
