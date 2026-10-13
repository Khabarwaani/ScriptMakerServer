# Workspace Rules & Development Guidance

All agents (including Antigravity, Codex, etc.) must follow the guidelines specified below.

## Mandatory Agent Git Worktree Workflow

Before starting any implementation or making any edits:

1. **Dedicated Worktree**:
   - Every coding agent **must** create or use a dedicated Git worktree located at `.worktrees/<agent>` (e.g. `.worktrees/antigravity` for Antigravity, `.worktrees/codex` for Codex).
   - **NEVER** edit files or checkout feature/bug branches directly in the primary repository root. All task execution, code edits, and testing must be performed within `.worktrees/<agent>`.

2. **Branching & Setup**:
   - Fetch the latest `develop` from origin:
     ```sh
     git fetch origin develop
     ```
   - For bugs, search GitHub issues (`gh issue list`) or create one (`gh issue create`). Use the issue number in the branch name (e.g., `bug/123-short-description`).
   - For non-bug tasks, use a descriptive branch name (e.g., `chore/short-description`).
   - Create and attach the worktree:
     ```sh
     git worktree add -b <branch-name> .worktrees/<agent> origin/develop
     ```
   - If the worktree already exists, inspect it before reuse. Preserve unfinished work; never overwrite or delete active unmerged work.

3. **Subagent Execution**:
   - When invoking subagents to inspect or modify code, ensure their commands and workspace target `.worktrees/<agent>`.

4. **Integration, PR & Cleanup**:
   - Pull the latest `develop` before submitting a PR:
     ```sh
     git pull --no-rebase origin develop
     ```
   - Push only the task branch and create a PR targeting `develop`:
     ```sh
     git push -u origin HEAD
     gh pr create --base develop ...
     ```
   - Direct pushes to `develop` are strictly forbidden.
   - Squash merge issue PRs (`gh pr merge <number> --squash`), except version-only PRs which use regular merge (`--merge`).
   - Once verified merged on `origin/develop`, pull `develop` in the primary checkout, remove the clean worktree (`git worktree remove .worktrees/<agent>`), and delete the task branch (`git branch -d <branch>`).

See [Documentation/README.md](file:///Users/abhiraj/Documents/Khabarwaani/ScriptMakerServer/Documentation/README.md#L155-L252) and [Documentation/AGENTS.md](file:///Users/abhiraj/Documents/Khabarwaani/ScriptMakerServer/Documentation/AGENTS.md) for complete details.

## Test-server isolation

- Every real server launched for tests or smoke checks must use `AGENT_SERVER_ENV=testing`.
- Read the testing port range and attempt limit from `Packages/AgentServer/config/server.json`.
  The executable automatically checks random distinct candidates, defaulting to
  9000–9999 and at most 30 attempts, and retries startup port collisions.
- Swift test launchers should use `TestingPortAllocator.withAvailablePort` with
  `ServerConfiguration.testingPorts`; report startup bind collisions as
  `TestingPortAllocator.AllocationError.portInUse` and keep ownership until cleanup.
- Use the selected listening address printed after startup for all test requests.
  Never test against development (8080) or production (8081), or choose an ad hoc port.
- Retain the process handle/PID for the test server you launch. Shut down only that
  process; never run a port-wide `AgentServer stop` for tests or stop another server
  to obtain a port. In-process router tests do not listen and need no port allocation.
