# AgentServer Swift package

Server release: **1.1.0**. Agent contract versions are independent.

A local Swift 6 server for explicitly registered, versioned agent packages using
Codex, Antigravity or Grok CLI providers. For setup, configuration and contributor
workflow, see the [repository guide](../../Documentation/README.md).

## HTTP API

- `GET /agents`: only `id`, `name` and available `versions` for each agent.
- `POST /execute`: one final schema-validated JSON value or a structured error.
  The optional `status` query parameter defaults to `false` and can be omitted.
- `POST /execute?status=true`: lifecycle/progress SSE plus one validated final
  result or terminal error. Raw provider text stays internal in both modes.
- `GET /status`: current server health and lightweight session execution records.
- `POST /executions/{execution_id}/cancel`: scoped execution cancellation.
- `GET /openapi.json`: full agent contracts and provider metadata.

The `/help`, `/try` and execution pages include the **Show status updates** checkbox
and Copy controls for requests, responses, schemas, examples and results.

## Build and check

From the repository root:

```sh
swift build --package-path Packages/AgentServer
swift test --package-path Packages/AgentServer
swift run --package-path Packages/AgentServer AgentTools check --build
swift run --package-path Packages/AgentServer AgentTools docs
swift run --package-path Packages/AgentServer AgentTools docs --check
swift run --package-path Packages/AgentServer AgentServer
```

Agent availability requires a declared Swift package dependency, an
`AgentPackageContract` conformance and explicit registration in
`AgentRegistry.registeredPackages`. Update declared versions and rebuild to include
resource changes. Adding Markdown directories alone does not make an agent available.

The build generates validated schemas and documentation for `/help`. Checked-in
agent READMEs use the same generator; refresh them with `AgentTools docs` after
editing resources and commit the updated files. `docs --check` detects drift without
writing. Agent creation and version tooling refresh the affected README automatically.
Author version notes in `notes.md` rather than editing generated agent READMEs.

Follow [AGENTS.md](AGENTS.md) for the issue, worktree, PR, merge and cleanup workflow.

## Session execution logs

Open **Execution logs** from `/help` to list execution IDs, times and states,
with expandable timing and error details. `/execution-logs` returns the latest
200 state entries; `/execution-logs/download` streams the full JSONL file.
The server writes this file in its temporary `AgentServer` directory, prints its
path on startup, and clears it on a fresh start. It records accepted executions
and outcomes without prompts, results or raw provider output. Failed tracked
requests also retain a bounded error code and message; shutdown purges memory.
