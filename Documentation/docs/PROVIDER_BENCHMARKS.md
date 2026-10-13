# Provider latency and worker reuse

Opt-in local checks on 2026-10-13, feature #39 initially based on `a126746`,
then integrated with develop `99837f7`,
macOS and Swift 6. All rows use NewsResearcher 1.1.0 or ScriptRefiner 1.1.0,
the same public TfL research topic/source and a fictional continuity script with
`output_count: 1`. Model and reasoning effort are omitted, preserving installed
CLI defaults. Results are validated against the published agent schema.

## Swift end-to-end measurements

Seconds include readiness, preparation, queue, startup, generation, validation and
cleanup. Each cell is one request, not an average or a controlled speedup estimate.

| Provider | Agent | Fresh adapter | Automatic cold | Automatic second | Second reused |
| --- | --- | ---: | ---: | ---: | --- |
| Codex | NewsResearcher | 28.169 | 22.293 | 25.527 | Yes |
| Codex | ScriptRefiner | 36.976 | 28.439 | 27.626 | Yes |
| Grok | NewsResearcher | 28.978 | 17.162 | 18.614 | Yes |
| Grok | ScriptRefiner | 14.487 | 13.497 | 16.563 | Yes |
| Antigravity | NewsResearcher | 34.602 | 29.277 | 30.689 | No |
| Antigravity | ScriptRefiner | 15.611 | 15.911 | 43.574 | No |

The initial 18 executions completed with validated results. The Codex rows above
are a second six-request check after latest develop integration, also successful.
The Grok and Antigravity rows show the initial checkpoint; further checks below
record compatibility fixes and provider limitations. Native Codex request threads
were deleted and verified unloaded; Grok advertised and confirmed session close.
Antigravity has no verified context reset and remains fresh. Grok explicit
model/effort overrides also remain fresh until native configuration parity is
verified. Native protocol and cancellation mechanics additionally use deterministic
child-process fixtures; killing real in-flight model/tool work was not needed.

Initial Codex research checks exposed optional properties rejected by native strict
output (#44). The final table uses the schema bridge fix. The agent's original
schema remains authoritative and unchanged.

Latest develop introduced master feasibility errors. Its root `oneOf` was rejected
by Antigravity, which requires an object root (#46). An object declaration alone
avoided launch rejection but failed final-result framing. Codex and Antigravity
now use an explicit private native `output`/`error` envelope, removed before public
responses and original domain validation. This supports either a domain result or
a direct feasibility error without exposing transport fields or changing schemas.

Grok native research emits provisional assistant commentary before tool activity
and final JSON afterward (#48). The adapter now resets the result candidate at
explicit ACP tool boundaries and parses the whole final segment strictly. A public
TfL protocol probe reproduced this framing, and deterministic tests cover the fix
and reject commentary mixed into the final segment. Subsequent live Grok checks
were rejected by the backend (`session/prompt`, code -32003, rate/limit diagnostic),
including fresh CLI checks; these failures are not reported as successful reuse.

A transient CPU-pressure queue during an intermediate Codex comparison exposed a
missing maintenance loop in the benchmark harness. It now runs the same periodic
maintenance as the server, so queued work is reconsidered when pressure clears.
The final Codex table uses the corrected harness; resource limits were unchanged.

Generation dominates these runs. Warm totals vary in both directions. Fresh
Antigravity cleanup can also take several seconds after a terminal result, so a
benchmark should not attribute total latency solely to process launch. Diagnostic
phase timings distinguish these costs. Fresh startup ends at the observed ready
frame where available; otherwise initialization overlaps generation.

## Existing Python bridge comparison

The sibling application's unmodified `DualEngine` was invoked with matching
prompts, inputs, versions and one script variation, followed by the same schema
validation. Temporary comparison artifacts are outside the repository.

| Provider | NewsResearcher seconds/status | ScriptRefiner seconds/status |
| --- | --- | --- |
| Codex | 23.313 / JSON parsing failure | 31.738 / completed |
| Grok | 20.848 / completed | 14.865 / completed |
| Antigravity | 43.808 / completed | 27.005 / completed |

Both bridges launch fresh processes in their fresh modes. Python Codex does not
pass a native output schema; its default JSON extraction failed one research run.
Python Grok disables web search/planning/subagents, so its research timing is **not
an equivalent workload**. Native protocol tool/default-model behavior can also
differ; an omitted CLI model is not proof that every transport selected the same
effective model. These rows do not establish a Swift-versus-Python performance
advantage. A controlled comparison must pin matching models, effort and tools.

Earlier local API inspection showed `/agents` around 8 ms and `/status` around
12 ms, with executions around 30–54 seconds and one queue wait around 146 seconds.
Readiness is cached for 30 seconds and precedes accepted tracking. Those observations
do not demonstrate a fresh login on every request. The pool reduces repeat setup
and context cleanup where supported; it cannot remove model generation or busy
queue limits.

## Reproduce

Run `AgentTools benchmark codex`, substituting `grok` or `antigravity`, from the
Swift package build. It makes six real requests per provider, has a 180-second
execution/queue deadline, prints operational JSON measurements without prompts or
results, and shuts its workers down on completion. This is separate from unit
tests and uses the current user's CLI login. See [RUN.md](RUN.md) for configuration.
