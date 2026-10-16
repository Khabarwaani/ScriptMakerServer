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
  the GitHub issue number, for example `bug/123-execution-timing`. GitHub Issues is
  the bug tracker: search for an existing issue with `gh issue list`, and create
  missing bugs with `gh issue create` before fixing them. Do not create local bug
  tracker files. Follow the commands in [README.md](README.md#bug-tracking-and-agent-worktrees).
  For tasks that are not bugs and have no issue, use a descriptive
  task branch name, for example `chore/agent-worktree-instructions`.
- If the agent's named worktree already exists, inspect it before reuse. Preserve
  unfinished work and never overwrite or delete it to start a new task.
- Finish the changes, run the checks appropriate to the task, and commit them in
  the agent's worktree.
- Before merging, pull the latest remote `develop` into the task branch
  (`git pull --no-rebase origin develop`). Resolve conflicts in the agent's worktree
  and rerun affected checks. Push only the task branch (`git push -u origin HEAD`)
  and create a pull request targeting `develop` with `gh pr create --base develop`.
  Link its GitHub issue in the PR description. Direct pushes to `develop` are
  forbidden; all changes must go through a pull request.
- Merge every issue PR with squash merge (`gh pr merge <number> --squash`). The only
  exception is a PR solely for a version increase: use a regular merge preserving
  commits (`gh pr merge <number> --merge`). A PR that also fixes bugs or changes
  behavior must use squash merge. Satisfy required checks and reviews before merging;
  do not bypass protections. If `develop` advances, update the task branch, resolve
  conflicts, rerun affected checks and push the task branch again before merging.
- Verify that the PR is merged and its resulting commit is on remote `develop`.
  Sync the primary `develop` checkout with `git pull --ff-only origin develop` for
  integration cleanup, close the linked issue if needed, and remove the agent's
  clean worktree. Then delete the completed local task branch using
  `git branch -d <task-branch>`; removing a worktree alone does not delete its branch.
- A squash merge may prevent Git from recognizing the original branch as merged.
  Before using `git branch -D <task-branch>`, verify the PR targets `develop` and is
  merged, its merge commit is an ancestor of remote `develop`, and the local branch
  tip exactly matches the merged PR's `headRefOid`. Otherwise preserve the branch
  and investigate its additional or unmerged work. For legacy branches without a
  PR, delete only when their tip is already an ancestor of `develop`.
- Never delete `develop`, `main`, or a branch checked out in any active worktree.
  Never force-remove a dirty worktree. Keep the worktree and branch if PR creation,
  checks, merge, or verification fails; never discard unfinished work. Finish every
  task by checking `git worktree list` and `git branch -vv` for leftover task state.

## AgentAtom ownership

AgentAtom's canonical repository is `abhi266raj/AgentAtom`, release `0.0.1`.
`Packages/AgentAtom` is a retained snapshot until the explicit remote-dependency
migration is completed. Develop package changes upstream, then synchronize through
reviewed changes. Do not silently switch NewsAgent's manifest or update lockfiles
as part of documentation or publication work. See `docs/AGENTATOM_PUBLICATION.md`.
