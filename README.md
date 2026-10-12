# AgentServer

A Swift package for a local, provider-independent AI agent server. Open
`AgentServer.xcworkspace` in Xcode and select the AgentServer scheme to run it.
`AgentServer.xcodeproj` and `Package.swift` are also included.

**Current stage: runnable bootstrap, not the completed Version 1 server.**
The package starts a persistent HTTP service with an input page at `/`, detailed
API help at `/help`, and `GET /status`. The Run button previews/submits agent ID,
optional version, provider and arbitrary JSON input; `/execute` currently returns
a structured HTTP 501 error. Runtime agent
discovery, execution, SSE, schema validation, provider adapters, execution tracking
and cancellation are specified but not yet implemented. The sample agent is
configuration for future discovery and is not currently executable.

## Documents

- [Version 1 requirements](docs/SPECIFICATION.md)
- [Setup, run and test instructions](docs/RUN.md)
- [Architecture and implementation plan](docs/ARCHITECTURE.md)
- [Contributor instructions](AGENTS.md)

## Quick start

Requires macOS 14 or later, Xcode with Swift 6 or a Swift 6 toolchain, and network
access for the initial SwiftPM dependency download.

```sh
swift package resolve
swift build
swift test
swift run AgentServer
```

In another terminal:

```sh
curl http://127.0.0.1:8080/status
```

Stop the server with Control-C. See [RUN.md](docs/RUN.md) for configuration and
Xcode instructions.

Open `http://127.0.0.1:8080/` for the browser input page.

## Package layout

```text
Package.swift                 SwiftPM dependencies and targets
AgentServer.xcworkspace/      Main Xcode entry point
AgentServer.xcodeproj/        Xcode executable project and shared scheme
project.yml                  Reproducible XcodeGen project definition
Sources/AgentServer/          Hummingbird executable and HTTP routes
Sources/AgentCore/            Reusable server configuration and future core logic
Tests/AgentCoreTests/         Deterministic tests
Agents/NewsResearcher/1.0.0/  Example runtime agent definition
docs/                        Requirements, architecture and run instructions
```

HTTP uses [Hummingbird 2](https://docs.hummingbird.codes/2.0/documentation/hummingbird/).
The execution streaming protocol selected for Version 1 is SSE. Agent Markdown
files stay outside compiled targets so new versions can be discovered at runtime.
Commit `Package.resolved` to make server builds reproducible; `.gitignore` excludes
build output, local IDE state, logs and credentials.
