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
| `port` | `8080` | TCP port, from 1 through 65535 |
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
`AGENT_SERVER_PORT` overrides its port; `AGENT_SERVER_AGENTS_DIR` overrides its agent
root. Agent paths remain relative to the built asset root unless absolute.

```sh
AGENT_SERVER_PORT=9090 swift run --package-path Packages/AgentServer AgentServer
```

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

First test the small `JSONEcho` agent with each provider:

```sh
curl -N -X POST http://127.0.0.1:8080/execute \
  -H 'Content-Type: application/json' \
  -H 'Accept: text/event-stream' \
  -d '{"agent_id":"JSONEcho","provider":"codex","input":{"text":"hello"}}'
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

The run page separates lifecycle/heartbeat information, provider text, the validated
final result and expandable raw events. Provider output can appear before a validation
failure; it is not proof of successful completion. Heartbeats are approximately every
10 seconds and do not prove model progress.

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
```

Generated packages include a manifest, README, Swift definition accessor, resource
tests, role, instructions and output schema. Input schema is optional. Published
versions cannot be overwritten. Set an absolute `AGENT_SERVER_AGENTS_DIR` to create
or inspect packages in another root. Runtime additions need no rebuild; Swift resource
bundles contain the versions included at build time.

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
