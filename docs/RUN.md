# Setup and run

## Open in Xcode

1. Install Xcode and select its command-line tools if they are not already selected.
2. Open `AgentServer.xcworkspace` in Xcode, or run `open AgentServer.xcworkspace`.
3. Allow SwiftPM to resolve the Hummingbird dependency.
4. Select the `AgentServer` executable scheme and **My Mac** destination.
5. The shared scheme sets the working directory and agent root to the repository.
   Use an absolute `AGENT_SERVER_AGENTS_DIR` for deployments.
6. Run with Command-R. Stop with Xcode's Stop button.

The workspace references `AgentServer.xcodeproj`. The project links the local
`AgentCore` SwiftPM product and Hummingbird and copies web resources next to the
executable. You can alternatively open `Package.swift` directly and use SPM.
The project is generated from `project.yml`; after project-configuration changes,
run `xcodegen generate` (requires XcodeGen). Commit the generated project and shared scheme.

## Terminal

From the directory containing `Package.swift`:

```sh
swift --version
swift package resolve
swift build
swift test
swift run AgentServer
```

The foreground service stays available until stopped. Control-C requests graceful
shutdown through Hummingbird's service lifecycle. This bootstrap does not install
a background LaunchAgent.

```sh
curl --fail http://127.0.0.1:8080/status
```

The response contains `status: healthy`, `implementation_stage: bootstrap`,
server version and uptime, zero active executions and an empty execution list.
Open `http://127.0.0.1:8080/` for the input page and `/help` for API schemas and examples.
The Run button sends a POST request and shows the response incrementally.
`/execute` currently returns a structured 501 error. Discovery and cancellation
routes return the framework's 404;
the uniform error contract in the specification is still implementation work.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `AGENT_SERVER_PORT` | `8080` | TCP port, from 1 through 65535 |
| `AGENT_SERVER_AGENTS_DIR` | `Agents` | Absolute path or path relative to the working directory |

```sh
AGENT_SERVER_PORT=9090 AGENT_SERVER_AGENTS_DIR="$PWD/Agents" swift run AgentServer
```

The server binds to `127.0.0.1`. Remote binding will require authentication before
it is exposed as configuration. Environment configuration is read directly; no
`.env` loader is included. Provider installation and authentication will be
documented when the corresponding adapter has been verified and implemented.

For an optimized build:

```sh
swift build -c release
.build/release/AgentServer
```

## Future execution request

The following describes the planned API and will work after execution is implemented:

```sh
curl -N -X POST http://127.0.0.1:8080/execute \
  -H 'Content-Type: application/json' \
  -H 'Accept: text/event-stream' \
  -d '{"agent_id":"NewsResearcher","provider":"codex","input":{"topic":"India semiconductor industry","language":"English"}}'
```

`-N` disables curl output buffering. Obtain the execution ID from the response
header, `started` event or `/status`, then request cancellation:

```sh
curl -X POST http://127.0.0.1:8080/executions/EXECUTION_ID/cancel
```

## Troubleshooting

- Dependency resolution needs GitHub access. Retry `swift package resolve` when online.
- For an occupied port, stop the other service or set `AGENT_SERVER_PORT`.
- An invalid port fails startup before any socket is bound.
- Check `swift --version` and use Swift 6 or newer if the manifest is unsupported.
- Never commit credentials, runtime scratch directories or logs.

## Create the public GitHub repository

The initial automated attempt could not initialize `.git` because the workspace
restricts Git metadata writes. GitHub CLI also reported invalid authentication
and could not reach the API. No public repository has been created.

In your own terminal, after checking the files intended for publication:

```sh
gh auth login -h github.com
sh scripts/create-public-repository.sh Khabarwaani/ScriptMakerServer
```

The script initializes Git, commits the package and creates a public repository
in the Khabarwaani organization. Supply another owner/name as the final argument if desired.
