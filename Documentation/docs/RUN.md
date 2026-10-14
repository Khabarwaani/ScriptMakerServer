# Run and operate AgentServer

## Xcode

Open `AgentServer.xcworkspace` at the repository root. Select **AgentServer** and
**My Mac**, then press **Command-R**. Open `http://127.0.0.1:8080/` for the agent
input page and `/help` for collapsible instructions and dynamic agent schemas.
The shared scheme runs from build output; the build copies configuration, agent
definitions and web assets there. Runtime execution does not need to read the
source checkout in Documents.

To stop gracefully, select **AgentServer-Stop** and run it. Xcode's debugger Stop
button may terminate abruptly. The command sends SIGTERM to the managed server,
allows work to drain and waits for shutdown to finish. A fresh server launch uses
this same path to replace the previous managed instance on the configured port.
Unrelated applications using the port are never killed.

If Xcode reports `Missing package product 'Hummingbird'` or `ServiceLifecycle`,
first use **File > Packages > Resolve Package Versions**, wait for resolution to
finish, and rebuild. Both products are declared dependencies; the message can
occur while Xcode's package graph is unresolved. From the repository root, verify
resolution and the scheme with:

```sh
xcodebuild -resolvePackageDependencies -project AgentServer.xcodeproj -scheme AgentServer
xcodebuild -project AgentServer.xcodeproj -scheme AgentServer -destination 'platform=macOS,arch=arm64' build
```

Use `arch=x86_64` on an Intel Mac. If resolution fails, inspect its first error
for network or dependency diagnostics before changing package references or
deleting caches.

`GeneratedAgentValidationCatalog.swift` must remain in the AgentServer target's
**Compile Sources**. The **Validate Agents** build phase creates it in the derived
sources directory before compilation. Removing its project reference causes
missing `GeneratedAgentDocumentationRegistry` and `GeneratedAgentValidationCatalog`
errors; subsequent `.seconds` errors can be cascading diagnostics. Restore the
reference or regenerate the project from the configuration below, then rebuild.

The generated project lives at the repository root. To regenerate it:

```sh
xcodegen generate --spec Development/project.yml --project-root . --project .
```

## Terminal

From the repository root:

```sh
swift package --package-path Packages/AgentServer resolve
swift build --package-path Packages/AgentServer
swift test --package-path Packages/AgentServer
swift run --package-path Packages/AgentServer AgentServer
```

In another terminal:

```sh
curl http://127.0.0.1:8080/agents
curl http://127.0.0.1:8080/status
swift run --package-path Packages/AgentServer AgentServer stop
```

Control-C also triggers graceful shutdown when running in a terminal. A release
build is available with `swift build --package-path Packages/AgentServer -c release`.
Run the resulting executable with its adjacent SwiftPM resource bundle intact.

## Central configuration

Edit `Packages/AgentServer/config/server.json` and rebuild to update the packaged
defaults. The server reads the built copy, not the source file at runtime.

| Setting | Default | Meaning |
| --- | --- | --- |
| `host` | `127.0.0.1` | Loopback only; remote binding is unavailable |
| `environment` | `development` | `development`, `production`, or `testing` |
| `ports.development` | `8080` | Fixed development TCP port |
| `ports.production` | `8081` | Fixed production TCP port |
| `ports.testing.min` / `max` | `9000` / `9999` | Inclusive automatic testing port range |
| `ports.testing.max_attempts` | `30` | Maximum distinct candidates; configurable from 1 through 30 |
| `agents_directory` | `Agents` | Relative to built asset root, or an absolute runtime root |
| `shutdown_timeout_seconds` | `900` | Fifteen-minute graceful shutdown allowance |
| `execution_timeout_seconds` | `1800` | Running execution deadline |
| `max_processes` | `8` | Configurable process resource budget; not a five-process cap |
| `max_queued_executions` | `64` | Burst queue capacity |
| `retention_seconds` | `3600` | Retain terminal metadata for monitoring |
| `runtime_directory` | Application Support | Optional scratch-directory override |
| `providers` | codex, antigravity, grok | Enabled flag, executable and optional model |

Scratch files default to `~/Library/Application Support/Khabarwaani/AgentServer/Executions`
and are removed after execution termination. Credentials remain managed by the CLIs.

Environment overrides: `AGENT_SERVER_CONFIG` selects an explicit settings file;
`AGENT_SERVER_ENV` overrides the environment; `AGENT_SERVER_PORT` overrides the fixed
port or supplies the first testing candidate (which must lie within the test range).
`AGENT_SERVER_AGENTS_DIR` overrides its agent root. Agent paths remain relative to
the built asset root unless absolute. Legacy `port` settings remain supported as
a development default when `ports.development` is absent. Fixed ports and their
overrides must stay outside the testing range and cannot use the other fixed
environment's configured port.

```sh
AGENT_SERVER_ENV=development swift run --package-path Packages/AgentServer AgentServer
AGENT_SERVER_ENV=production swift run --package-path Packages/AgentServer AgentServer
AGENT_SERVER_ENV=testing swift run --package-path Packages/AgentServer AgentServer
```

Production and development use distinct fixed ports outside the configured test
range. Xcode Run and Stop schemes explicitly select development. Testing checks
availability by binding/listening on the configured loopback address before
selection, skips occupied candidates, and retries collisions during startup. It
tries at most 30 distinct candidates (or stops sooner if the range is exhausted).
Unrelated startup failures are reported immediately. The selected address is
printed only after the server has bound successfully, including when output is
captured by a test launcher.

Testing never replaces an existing managed server. All HTTP test callers must
use the selected address and terminate only their own process handle/PID. The
`AgentServer stop` command is rejected in testing mode, even with a port override.
Swift launchers can share `TestingPortAllocator.withAvailablePort` and
`ServerConfiguration.testingPorts`; the operation must retain the listener or
server instance until cleanup and report startup collisions as `portInUse`.
In-process `.router` tests need no listener. No AI-provider settings or HTTP
contracts change with the selected environment.

Accepted work drains for up to 900 seconds during shutdown. The service exits sooner
when cleanup finishes. Remaining jobs are cancelled at the deadline, with a bounded
process termination period. Replacement startup waits for the old instance to
release its kernel lock and never force-kills an old server after the allowance.

## Provider setup and execution

The server inherits the user environment and reuses existing Codex, Antigravity and
Grok CLI logins. There is no new server login. Configure absolute executable paths
if Xcode's PATH does not include them, and optional model IDs to override CLI defaults.
Codex checks cached login status. Antigravity/Grok perform local initialization checks
without querying remote model lists; expired or inaccessible credentials are reported
when the actual provider attempts execution.

Test ScriptRefiner with a sample script using each provider:

```sh
curl -N -X POST 'http://127.0.0.1:8080/execute?status=true' \
  -H 'Content-Type: application/json' \
  -H 'Accept: text/event-stream' \
  -d '{"agent_id":"ScriptRefiner","provider":"codex","input":{"script":"INT. OFFICE - DAY\nJOHN (laughing)\nI lost everything."}}'
```

Replace `codex` with `antigravity` or `grok`. These are opt-in live integration calls
and may consume provider usage. Unit tests use mock providers and synthetic CLI frames.
The adapters keep provider permission checks enabled and do not bypass authentication
or sandbox safeguards.

Codex uses JSONL events, native schema output and a final-message file. Antigravity
uses `step_update.text_delta`, safe step progress and the terminal structured result.
The adapter separates its known string `toolAction`/`toolSummary` transport annotations
only when they are not declared by a strict root output schema. Arbitrary extra fields
are never removed to make validation pass. Grok uses headless streaming-message events;
its final JSON is independently schema-validated.

## Output, monitoring and cancellation

POST /execute returns only the final schema-validated JSON value or a structured
error by default. Omit `status` or pass `status=false`. Use
`POST /execute?status=true` to receive lifecycle/progress SSE and one validated result
or terminal error. Raw provider output is internal in both modes.

The run page and help/Try page provide an unchecked Show status updates checkbox.
Help and Try pages include Copy buttons for requests, responses, schemas, examples,
results and raw events. Clipboard failures are shown on the button; fallback copy
is available when the browser Clipboard API is unavailable.

Status heartbeats are approximately every 10 seconds and do not prove model progress.
In final-only mode, the execution ID header arrives with the final response. In status
mode it arrives immediately with the started event. Use GET /status to monitor while
waiting for a final-only response.

Read the execution ID from `X-Execution-ID`, the first event or `/status`. Cancel it:

```sh
curl -X POST http://127.0.0.1:8080/executions/EXECUTION_ID/cancel
```

Cancellation is scoped and idempotent. The state remains cancelling until the execution
process has stopped. Closing a browser/HTTP stream detaches output and keeps execution
running. There is no reconnect endpoint or resumable stream in Version 1.

## Swift agent tooling

```sh
swift run --package-path Packages/AgentServer AgentTools add MyAgent 1.0.0
swift run --package-path Packages/AgentServer AgentTools check
swift run --package-path Packages/AgentServer AgentTools check --build
swift run --package-path Packages/AgentServer AgentTools version MyAgent 1.1.0 1.0.0
swift run --package-path Packages/AgentServer AgentTools docs
swift run --package-path Packages/AgentServer AgentTools docs --check
```

Generated packages include a manifest, README, Swift definition accessor, resource
tests, generated README, role, instructions and output schema. Input schema is optional. Published
versions cannot be overwritten. Set an absolute `AGENT_SERVER_AGENTS_DIR` to create
or inspect packages in another root. Only explicitly linked and registered packages
are available. Rebuild after declaring new versions; adding Markdown directories
alone does not update a running server. `docs` refreshes checked-in package READMEs
from the same resources used by generated help metadata; `docs --check` reports drift
without writing. Include that check before PRs and releases.

## Verification and troubleshooting

The package builds and has deterministic Swift tests for configuration, registry,
schema validation, provider event parsing, concurrency, cancellation and HTTP contracts.
This automation environment restricts socket binding and provider-specific user-folder
writes, so a live network/CLI smoke test must also be run from Xcode or your terminal.
Passing mock tests does not prove every provider account/backend is available.

If a model stays silent, inspect provider progress and its final state, rather than
assuming heartbeats represent response tokens. For validation failures, compare the
final output against the version-specific schema shown on `/help`.

macOS protects Documents through Files and Folders permissions. The built server's
asset/scratch paths avoid the source directory during normal runtime; explicit external
paths in Documents can still require permission. See Apple's documentation on
[controlling app access to files](https://support.apple.com/guide/security/controlling-app-access-to-files-secddd1d86a6/web).

Local-only setup helpers are in `ignoreGit/`, which is ignored. The public repository
already exists at https://github.com/Khabarwaani/ScriptMakerServer; recreating it is unnecessary.

## Session execution logs

Open **View execution logs** in `/help`, or go to `/logs`. The list shows execution
ID, acceptance time and latest status; **View details** reveals state history,
running duration and error code/message. It loads the latest 200 state entries;
**Download full log** streams all entries from the session without loading the
whole file into server memory.

The server creates `AgentServer/executions-<port>.jsonl` under the current user's
temporary directory after acquiring its instance lock and prints the path on
startup. A fresh start replaces that port's previous session log. Graceful shutdown
purges in-memory tracking; the file remains available on disk until the next start
or OS temporary-file cleanup. Each accepted execution logs queued/running and
terminal success, failure or cancellation; cancelling is also logged when used.
Rejected requests have no execution ID and return their error directly.

Only ID, state, timing and bounded error details are retained. No request bodies,
prompts, results, raw provider output or credentials are recorded. The log file is
private to the current user. Failed `/status` records also keep the code/message,
so the Tracked executions list explains their failure after the response ends.

## Global provider worker pool

`provider_pool_size` defaults to **5 retained workers total**, across all agents
and providers. Workers are created lazily and healthy workers have no idle expiry.
Compatibility includes provider/settings, agent version and schema. The server
reuses a compatible idle worker, evicts the least recently used idle worker when
needed, and never evicts busy work. Burst workers can exceed the retained size up
to `max_processes`; they are removed after their request. All idle/busy/burst
workers count toward process and memory limits. Memory pressure can reclaim idle
workers to avoid starving queued work. Set the retained size to `0` to disable
caching; it cannot exceed `max_processes`.

Codex uses its app-server protocol with a new request thread and native output
schema per request. The thread is deleted and checked as unloaded before reuse.
These owned request threads can create temporary Codex rollout files; normal
completion deletes them. Grok uses an owned `--no-leader` stdio process with a new
session per request and verified `session/close`. Interactive tool approvals are
not automatically granted. Antigravity remains on fresh stream-JSON processes:
its installed CLI advertises multiple turns, but no verified context reset.
Grok with explicit model/effort settings also stays fresh until its session
configuration parity is verified. A reset failure retires the worker and disables
reuse for that provider for this server session; failed inference is not replayed.

Provider entries optionally accept `reasoning_effort` and `worker_reuse` (false
forces the original fresh-process adapter). Omitted model/effort preserve CLI
defaults. `/status` and `/openapi.json` provider metadata report the current
`worker_reuse` mode. `/status` includes `worker_pool` counts and resident memory,
including idle workers. Execution/log records retain bounded `phase_timings`,
`queue_reasons` and `worker_reused`; the main page and log details display them.

Queue reasons are `process_limit`, `provider_memory`, `available_memory`, and
`cpu_load`. Readiness/preparation occurs before acceptance; `queue_seconds`
begins at acceptance. Startup/generation/validation/cleanup are measured
separately, and `total_seconds` starts at execution-manager entry. Do not add
`elapsed_seconds` to phase totals; it overlaps those running phases.

### Restart ownership cleanup

After acquiring the port's instance lock, the server reads the private
`Khabarwaani-AgentServer/workers-<port>.json` file in the user's temporary
directory. It records only process/owner identities (PID, start identity,
executable, UID and initial parent), not input, prompts or credentials. It stops
only verified workers whose previous owner is no longer that live server
identity. PID reuse, unknown identities and live owners are preserved. A malformed
or insecure ownership file fails startup closed; do not replace it with guessed
PIDs. Normal process exit removes the manifest entry.

There is **no supervisor process**. A server crash or SIGKILL can leave workers
alive until restart; provider-owned diagnostic/rollout files can also remain after
abnormal termination. Normal shutdown reaps the pool and fresh processes. macOS
identity checks are validated locally; Linux hooks use `/proc` identity and must
be validated on a Linux target. Windows reuse/restart signalling fails closed
until equivalent identity/ACL checks are implemented.

### Opt-in latency comparison

The following command makes real model requests with the installed CLI login:

```sh
swift run --package-path Packages/AgentServer AgentTools benchmark codex
# Substitute grok or antigravity.
```

It tests both NewsResearcher and ScriptRefiner (one requested script variation),
first with fresh adapters, then twice with automatic native workers. It prints
only operational measurements, versions, reuse mode and error codes. It never
prints prompts or results. Each execution is bounded to 180 seconds, including
queue wait; jobs rejected before acceptance are labelled rejected. This is
separate from deterministic unit tests and consumes provider capacity.

Compare matching inputs, agent versions, models, effort, tools and output counts.
The old Python bridge starts fresh processes too; its Grok path disables web and
planning, and its reasoning controls differ. A Python NewsResearcher run with web
research disabled is not an equivalent workload. Report these differences rather
than attributing them to Swift or pooling. Single-run numbers validate mechanics,
not statistically reliable generation speedups.

Codex strict-schema compatibility: the adapter makes optional domain properties
required/nullable only in the native transport schema, including nested objects.
It removes transport-added optional nulls before validating the final value against
the unchanged published agent schema. Required/originally nullable/unknown fields
are never stripped. Shapes not representable in native strict output use the same
JSON prompt and authoritative server-side validation without a native schema.
Fresh CLI startup ends at the observed initialization frame when available;
otherwise only OS launch is observable and initialization overlaps generation.

The master feasibility protocol is preserved for all adapters. Codex and
Antigravity use a private native `output`/`error` envelope for their supported
strict schemas, then remove it before returning the domain result or feasibility
error. Feasibility errors keep develop's direct HTTP 422 behavior and retire the
worker. Grok discards provisional pre-tool message segments at explicit ACP tool
boundaries; the complete final segment must still parse as JSON. See
[measured checks and limitations](PROVIDER_BENCHMARKS.md).
