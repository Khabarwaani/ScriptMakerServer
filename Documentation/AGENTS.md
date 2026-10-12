# Development guidance

The authoritative Swift package instructions and required folder layout are in
[Packages/AgentServer/AGENTS.md](../Packages/AgentServer/AGENTS.md).

Keep the repository root limited to Xcode entry points, `.gitignore`, and grouped
`Packages`, `Documentation`, `Development` and ignored local-only `ignoreGit` folders.

## Agent Git workflow

- Every coding agent must create a separate Git worktree named after itself, such as
  `codex` for Codex or `antigravity` for Antigravity, and perform all task work there.
  Store worktrees in the ignored `.worktrees/` directory. Never use another agent's
  worktree or modify the primary checkout for task work.
- Create a task branch from the latest remote `develop`. Base the branch name on
  the bug ID, for example `bug/BUG-123`. If no bug ID exists, use a descriptive
  task branch name, for example `chore/agent-worktree-instructions`.
- If the agent's named worktree already exists, inspect it before reuse. Preserve
  unfinished work and never overwrite or delete it to start a new task.
- Finish the changes, run the checks appropriate to the task, and commit them in
  the agent's worktree.
- Before merging, pull the latest remote `develop` into the task branch
  (`git pull --no-rebase origin develop`). Resolve conflicts in the agent's worktree
  and rerun affected checks. Push the merged result to remote `develop`
  (`git push origin HEAD:develop`). If the remote advances before the push succeeds,
  pull, resolve, verify, and retry; never force-push `develop`.
- After verifying that remote `develop` contains the completed changes and the
  push succeeded, remove the agent's clean worktree. Keep the worktree if merging,
  verification, or pushing fails; never force-remove unfinished work.
