# AgentServer

A local Swift service for discovering and executing versioned AI agents through
Codex, Antigravity and Grok CLI adapters. HTTP uses Hummingbird; execution output
returns one final validated JSON value or error by default. Add `?status=true` for
optional status updates via Server-Sent Events (SSE). Agent definitions and provider implementations are
independent.

Open **AgentServer.xcworkspace**, select **AgentServer → My Mac**, and press **⌘R**.
Then open **http://127.0.0.1:8080/**. The input page discovers agent IDs and versions
from the registry. **GET /agents** returns only `id`, `name` and `versions` for each
agent; full contracts and provider metadata come from **/openapi.json**.
Display names come from `AgentPackageContract.name`, which defaults to the agent ID.
**/help** documents both response modes. Its **Show status updates** checkbox
configures Try it, and Copy buttons cover requests, responses, examples and schemas.
The help page dynamically displays each agent's
role and input/output contracts. Execution pages show start time and live running
duration. Tracking is limited to the current server session, purged on shutdown,
and retains only ID, state and timing after an execution finishes.

The four API routes, in-process scheduling, provider adapters, validation and
cancellation are implemented. See [run instructions](docs/RUN.md) for verification
limitations and CLI integration checks. Provider installation alone does not prove
that a provider's cached credentials or backend are available.

## Build, run and stop

Requires macOS 14+, Swift 6 and network access for initial dependency resolution.

```sh
swift package --package-path Packages/AgentServer resolve
swift build --package-path Packages/AgentServer
swift test --package-path Packages/AgentServer
swift run --package-path Packages/AgentServer AgentServer
```

Configuration is in [config/server.json](../Packages/AgentServer/config/server.json): loopback, port 8080,
15-minute graceful shutdown allowance, execution timeout, process/queue budgets,
status retention and provider executable/model settings. Built configuration, agent
definitions and web assets are served from the build output. Execution scratch
files default to Application Support rather than the source checkout.

Gracefully stop a running instance:

```sh
swift run --package-path Packages/AgentServer AgentServer stop
```

In Xcode, run the **AgentServer-Stop** scheme for the same behavior. A new server
instance gracefully stops the previous managed instance on its configured port
before starting. If shutdown does not finish within the allowance, startup fails
rather than force-killing the server. Unrelated port owners are left untouched.
Xcode's debugger Stop button may terminate abruptly; use the stop command for
cleanup that must be graceful.

## Standard project layout

```text
AgentServer.xcworkspace/               Xcode entry point
AgentServer.xcodeproj/                 Generated project and shared Run/Stop schemes
Development/project.yml               Reproducible XcodeGen configuration
Documentation/                        README, architecture and operations
Packages/AgentServer/
  Package.swift / Package.resolved     SwiftPM targets and pinned dependencies
  AGENTS.md                           Authoritative development instructions
  Sources/
    AgentServer/                      Composition root and API/ transport
    AgentCore/
      Configuration/                  Typed settings
      Models/                         JSON, errors, request/event/status models
      Registry/                       Discovery, snapshots and semantic versions
      Providers/                      CLI adapters and process I/O
      Execution/                      Scheduling, cancellation and cleanup
      Lifecycle/                      Instance replacement and graceful stop
      Validation/                     Supported JSON Schema assertions
      Tools/                          Swift package scaffolding and checks
    AgentResources/                   Build-time agent/config/web assets
    AgentTools/                       Swift developer tool executable
  Tests/
    AgentCoreTests/                   Deterministic core and mock-provider tests
    AgentServerTests/                 HTTP contract tests
  Agents/
    NewsResearcher/                   Research agent package
    ScriptRefiner/                    Script-refining agent package
  config/                             Central server configuration
ignoreGit/                            Ignored local helpers; never committed
```

Keep code with its owning feature. HTTP concerns belong in `AgentServer`; reusable
business logic belongs in `AgentCore` and must not import the HTTP framework.
Provider-specific command formatting and event parsing stay inside adapters.
Use Swift for package tooling and tests. Avoid miscellaneous utility folders,
duplicate configuration and domain-specific assumptions in the execution manager.

## Agent packages

Every agent is an independent SPM library package with this contract:

```text
Packages/AgentServer/Agents/AgentID/
  Package.swift
  README.md
  Sources/AgentID/AgentID.swift
  Tests/AgentIDTests/DefinitionTests.swift
  1.0.0/
    role.md
    instructions.md
    input.schema.json                 Optional input contract
    output.schema.json                Required final-result contract
```

Create and check packages using the Swift tool:

```sh
swift run --package-path Packages/AgentServer AgentTools add MyAgent 1.0.0
swift run --package-path Packages/AgentServer AgentTools check
swift run --package-path Packages/AgentServer AgentTools check --build
swift run --package-path Packages/AgentServer AgentTools version MyAgent 1.1.0 1.0.0
swift run --package-path Packages/AgentServer AgentTools docs
swift run --package-path Packages/AgentServer AgentTools docs --check
```

Write a complete role sentence, explicit workflow and constraints, and a supported
JSON Schema. Prefer a small, precise output contract with required fields and
`additionalProperties: false`. Never store credentials in definitions. Published
versions are immutable: change behavior by adding a version, not editing an existing
one. Clients may select an exact version, including a prerelease; automatic selection
uses the highest stable semantic version.

Swift packages embed the resources listed in their manifests at compile time.
Agent availability requires typed package linking and registration in `AgentRegistry.registeredPackages`.
The build automatically validates agent contracts, schemas and examples, and generates package documentation.
Adding or updating an agent or version requires updating package declarations and rebuilding the server;
undeclared or unbuilt additions remain unavailable.

The build generates embedded documentation for `/help`; it does not rewrite source
README files. `AgentTools docs` refreshes checked-in agent READMEs using that same
generator, including exact input/output schemas and current API behavior.
`AgentTools docs --check` detects drift without writing. Run it before a PR or
release, and commit regenerated READMEs after resource changes. Creation/version
commands refresh the affected README automatically. Write authored notes in
`notes.md`, rather than editing generated READMEs. See the
[AgentServer package README](../Packages/AgentServer/README.md) for the package entry point.

## Bug tracking and agent worktrees

Track bugs in [GitHub Issues](https://github.com/Khabarwaani/ScriptMakerServer/issues)
using the GitHub CLI (`gh`), rather than local bug tracker files. Include the
reproduction steps, actual behavior, expected behavior and verification criteria.
Search existing issues first to avoid duplicates:

```sh
gh issue list --repo Khabarwaani/ScriptMakerServer --state open
gh issue create --repo Khabarwaani/ScriptMakerServer --label bug \
  --title "Brief description of the bug" --body-file /tmp/bug-description.md
gh issue view 123 --repo Khabarwaani/ScriptMakerServer
```

Write the issue description to `/tmp/bug-description.md` before running the create
command. Use the issue number returned by GitHub in the branch name. Each agent
works only in a worktree named after itself (`codex`, `antigravity`, etc.). From
the repository root, this example starts a Codex fix for issue 123:

```sh
git fetch origin develop
git worktree add -b bug/123-short-description .worktrees/codex origin/develop
cd .worktrees/codex
```

Inspect an existing agent worktree before reusing it; preserve unfinished work.
For a task without a bug/issue, use a descriptive branch name. After finishing
the fix and running the required checks, commit with the issue reference, pull
the latest `develop` into the task branch, resolve any conflicts and rerun affected
checks before pushing only the task branch and opening a pull request into `develop`:

```sh
git add <changed-files>
git commit -m "fix: describe the change (fixes #123)"
git pull --no-rebase origin develop
git push -u origin HEAD
gh pr create --repo Khabarwaani/ScriptMakerServer --base develop \
  --head bug/123-short-description --title "Fix the reported bug" \
  --body-file /tmp/pr-description.md
```

Write `/tmp/pr-description.md` with the problem, resulting behavior, validation
and `Fixes #123` before creating the PR. Direct pushes to `develop` are forbidden:
every change must go through a PR targeting `develop`. Satisfy required checks and
reviews; do not bypass branch protections. If `develop` advances before merging,
pull it into the task branch, resolve conflicts, rerun affected checks and push the
task branch again.

Squash merge every issue PR. The only exception is a PR solely for a version
increase, which uses a regular merge preserving commits. A PR containing a bug fix
or behavior change must use squash merge even if it also increases a version.
Replace `<pr-number>` with the PR number returned by GitHub:

```sh
gh pr checks <pr-number> --repo Khabarwaani/ScriptMakerServer
gh pr merge <pr-number> --repo Khabarwaani/ScriptMakerServer --squash
# Only for PRs solely increasing a version, use --merge instead of --squash.
gh pr view <pr-number> --repo Khabarwaani/ScriptMakerServer \
  --json state,mergedAt,mergeCommit,baseRefName,headRefName,headRefOid
git fetch origin develop
git merge-base --is-ancestor <merge-commit-sha> origin/develop
```

Verify that the PR is merged and its resulting commit is on remote `develop`.
Return to the primary checkout and sync local `develop` for integration cleanup,
then close the issue if it was not closed automatically:

```sh
cd ../..
git pull --ff-only origin develop
gh issue close 123 --repo Khabarwaani/ScriptMakerServer --reason completed
git worktree remove .worktrees/codex
git branch -d bug/123-short-description
```

Removing a worktree does not delete its local branch. Delete both after the PR
merge is verified and local `develop` is synced. Squash merging creates a new
commit, so `git branch -d` may refuse deletion even though the PR is merged. Before
using `-D` after such a refusal, verify all of the following: the PR state is `MERGED`, its base is
`develop`, its merge commit is an ancestor of `origin/develop`, and the local task
branch tip equals the PR's `headRefOid`. Use `git rev-parse` to compare the local
tip with the head returned by `gh pr view`:

```sh
git rev-parse bug/123-short-description
# Only after the checks above confirm there are no extra local commits:
git branch -D bug/123-short-description
git worktree list
git branch -vv
```

If the branch tip differs from the merged PR head, preserve it and investigate its
additional work. For legacy branches without a PR, delete only if their tip is
already an ancestor of `develop`. Never delete `develop`, `main`, or a branch
checked out in an active worktree; never force-remove a dirty worktree. Keep the
worktree and branch when PR creation, checks, merge or verification fails. See
[AGENTS.md](AGENTS.md) for the required workflow.

## Engineering practices

- Use Swift Concurrency and actor-owned mutable execution state. Keep request data,
  process handles, stream state and cancellation isolated per execution.
- Pass CLI arguments as argument arrays; never interpolate client data into shell commands.
- Reuse the user's existing CLI login and configuration. Do not implement a parallel
  credential store or request a fresh login for every execution.
- Treat provider output as untrusted. Parse final JSON and validate the selected
  output schema before emitting `result` and `completed`.
- Reject unsupported schema assertions; do not silently skip validation constraints.
- Bound process creation, queued work, output buffers, result size and status retention.
  Default process capacity exceeds five and can be configured for available resources.
- Stop only owned processes. Release pipes, process handles and execution scratch
  files after termination. Retain operational metadata, not prompt payloads.
- Keep loopback binding. Remote authentication must be implemented before enabling
  remote access. Sanitize client-facing errors and avoid logging secrets or full prompts.
- Use mock providers for deterministic tests. Keep real-provider integration checks
  separate and opt-in because they depend on authentication, network and model availability.
- Run `swift build`, `swift test` and agent-package checks before publishing changes.
  Commit `Package.resolved`, manifests, shared schemes and generated project changes;
  exclude credentials, caches, local IDE state, logs and `ignoreGit/`.
- Use focused Conventional Commit messages and reviewable pull requests. Describe
  behavior, verification and remaining limitations; do not claim unverified acceptance criteria.

The authoritative contributor rules and required folder structure are in
[AGENTS.md](AGENTS.md); [agent.md](agent.md) points to that guide.

## Documentation

- [Requirements specification](docs/SPECIFICATION.md)
- [Architecture and decisions](docs/ARCHITECTURE.md)
- [Setup, configuration, API examples and troubleshooting](docs/RUN.md)
- [Hummingbird service lifecycle](https://docs.hummingbird.codes/2.0/documentation/hummingbird/servicelifecycle/)
- [Codex non-interactive execution](https://developers.openai.com/codex/noninteractive/)
- [Antigravity headless execution](https://www.antigravity.google/docs/cli/headless/)

Repository: [Khabarwaani/ScriptMakerServer](https://github.com/Khabarwaani/ScriptMakerServer).
