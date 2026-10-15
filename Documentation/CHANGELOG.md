# Changelog

## 3.0.0

- Introduce `ShekharJokeGenerator` Hindi news comedy agent:
  - Generates sharp, indirect news satire inspired by Shekhar Suman in everyday spoken Hindi (बोलचाल की हिंदी).
  - Configurable inputs: `output_count` (default 1), `news_count` (default 3), and `jokes_per_category` (default 2) (#103, #104).
  - Top-level `items` output array containing dual jokes (short <= 30 words, long <= 60 words) and formatted broadcast scripts without mock/example data (#94, #98, #104).
- Introduce standalone `NewsAgent` Swift package conforming to `AgentAtom.ModelledSpec` (#96).
- Introduce `AgentAtom` framework for lightweight typed agent specifications, native guided JSON generation, lifecycle operations, streaming execution, and Apple Intelligence local session integration (#87, #88, #89, #92).
- Apply first-listen clarity guidance to all agent generations across the server (#102).
- Report provider exit status and termination signals transparently in terminal status and session logs without unverified authentication assumptions (#95, #97).
- Support headless and interactive execution with Antigravity provider using `--dangerously-skip-permissions` (#94, #98, #99, #100).
- Add independent agent packages: `ReelIdeaGenerator` (#66), `ThemeMixer` (#67), `DialogueGenerator` (#68), and `ReelJokeMaker` (#69, #70).
- Enforce natural conversational connection, tight cause-and-effect flow, and real-world human plausibility across all dialogue and script agents (#83, #85).
- Dedicated agent format inspection page, schema-form controls, and contract examples on Try pages (#74).
- Deprecate and remove legacy `ScriptRefiner` v1.0.0 following verification of v1.2.0 (#47, #82).
- `/status`, `/openapi.json`, and RPC client info report server version 3.0.0 (#105).

## 2.0.0

- Separate configurable development (8080), production (8081), and automatic
  testing ports (9000–9999). Tests check availability, retry up to 30 distinct
  candidates, and never replace or stop existing servers (#52).
- Explicit target port reclamation during server launch, cleanly reaping managed
  listening processes on the target port (#55).
- Deterministically populate declared schema defaults into agent execution inputs
  prior to validation and provider execution, and remove invalid static JSON placeholder
  in web UI (#53).
- Dedicated agent documentation (`/agents/{agent_id}` and `/help/agents/{agent_id}`)
  and dedicated Try pages (`/agents/{agent_id}/try` and `/try/agents/{agent_id}`)
  alongside central help and try pages (#61).
- Add DialogueRefiner agent and schema-driven Try inputs for all agents (#60).
- Add configurable lazy global `provider_pool_size` (default five), idle LRU,
  bounded burst workers, verified native context reset and error retirement (#39, #50).
- Add private process-identity journaling and safe restart cleanup after forced
  server termination; no supervisor is added and unknown processes are preserved.
- Add pool counts/memory, reuse modes, execution phase timings and queue reasons to
  status/logs/help, plus opt-in real-provider benchmark tooling.
- Translate Codex native strict schemas for optional fields without modifying
  immutable agent contracts or bypassing their final-result validation (#44).
- Preserve master feasibility errors through native Codex/Antigravity envelopes
  and separate Grok pre-tool commentary from final JSON at protocol boundaries (#40, #46, #48).
- Failed tracked requests retain bounded error code/message so their failure reason
  remains visible after completion (#36).
- A per-port temporary JSONL execution log records session state transitions and
  outcomes, resets on a fresh start, and is available through Help's `/logs` viewer
  and full-log download. Recent reads and downloads use bounded memory (#38).
- ScriptRefiner 1.2.0 adds scene timing constraints, dialogue words-per-second (WPS)
  pacing, and dialogue overflow detection. Refined scripts include per-scene timing
  breakdowns divided into dialogue and non-dialogue durations with comprehensive
  post-generation verification. Existing versions 1.0.0 and 1.1.0 remain unchanged (#45).
- ScriptRefiner 1.1.0 adds automatic full prop lifecycle, character, spatial and
  action continuity audits across every script point, shot and subscene. Both input
  issue/focus options and detected-issue categories include the new continuity
  types; 1.0.0 remains available unchanged (#37).
- Formalize three-tier architecture separating presentation (`AgentServer`), core
  orchestration (`AgentCore`), and domain packages (`Agents/*`) (#42).
- `/status`, `/openapi.json`, and RPC client info report server version 2.0.0.

### Migration

Update clients and scripts relying on single-port behavior: development defaults to
8080, production defaults to 8081, and automated tests use ephemeral allocations in
9000–9999. In-process clients and schemas remain backward-compatible; agent contract
versions remain independent of the server major version.

### Verification

Native macOS Swift build, 97 server and core unit tests (including /status and
OpenAPI version assertions), automatic input contract discovery tests, standalone
agent-package builds via `AgentTools check --build`, and README drift checks via
`AgentTools docs --check`. Deterministic mock providers ensure hermetic testing.

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
