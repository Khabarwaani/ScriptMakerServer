# Changelog

## Unreleased

- Failed tracked requests retain bounded error code/message so their failure reason
  remains visible after completion.
- A per-port temporary JSONL execution log records session state transitions and
  outcomes, resets on a fresh start, and is available through Help's `/logs` viewer
  and full-log download. Recent reads and downloads use bounded memory.
- ScriptRefiner 1.2.0 adds scene timing constraints, dialogue words-per-second (WPS)
  pacing, and dialogue overflow detection. Refined scripts include per-scene timing
  breakdowns divided into dialogue and non-dialogue durations with comprehensive
  post-generation verification. Existing versions 1.0.0 and 1.1.0 remain unchanged.
- ScriptRefiner 1.1.0 adds automatic full prop lifecycle, character, spatial and
  action continuity audits across every script point, shot and subscene. Both input
  issue/focus options and detected-issue categories include the new continuity
  types; 1.0.0 remains available unchanged.

## 1.1.0

- `POST /execute` returns one final schema-validated JSON value or structured error
  by default. Use `?status=true` for lifecycle/progress SSE and the validated result;
  raw provider output stays internal.
- `GET /agents` returns only agent IDs, display names and available versions.
- Help and execution pages provide the status checkbox and Copy controls.
- Execution tracking includes start time and running duration. Terminal records
  retain only ID, state and timing; shutdown purges session records.
- Agents use explicitly linked Swift packages with typed registration, build-time
  resource validation and generated help metadata.
- `AgentTools docs` refreshes checked-in package READMEs; `docs --check` detects
  drift. Package guides include exact schemas and the current API behavior.
- `ScriptRefiner` replaces `ScriptWriter`. See its generated package README for
  the current input and output contracts. NewsResearcher exposes version 1.1.0.
- Platform delegates separate macOS, Linux and Windows implementation concerns.
- `/status` and `/openapi.json` report server version 1.1.0.

### Migration

Clients consuming SSE must add `status=true`; an Accept header alone does not enable
streaming. Update `ScriptWriter` requests to `ScriptRefiner` and its current input
schema. Agent contract versions are independent of the server release version.

### Verification

Native macOS Swift build and server/core tests, standalone agent-package tests,
schema validation and README drift checks. Provider behavior uses deterministic
mocks; live provider backend/authentication and Linux/Windows execution remain
separate integration checks.
