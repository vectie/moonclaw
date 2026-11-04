# Worktree And Subplan

A subplan describes task decomposition. A worktree provides a separate Git
working copy. Neither implies the other.

## Existing Boundaries

Generic job decomposition lives in `job/adaptive_subplan.mbt` and the job
execution path. Git worktree mechanics live in `internal/worktree` and the
existing worktree tools. Keep planning decisions separate from workspace
creation, branch identity, cleanup, and artifact handoff.

For native MoonCode delegation, the current worker tools require caller-supplied
isolated roots. They do not automatically provision worktrees or provide a
global file lock. A result reference does not grant access to another root.

## Selection

Default to one primary agent for a coding task. Use background commands or safe
tool concurrency before introducing another agent. A bounded delegated task
needs clear inputs, output, scope, and an integration owner.

Choose a worktree when separate authored changes or branch trials require it.
Read-only investigation does not automatically need a checkout. Worktree
isolation does not replace process sandboxing, authority, or integration checks.

Keep these choices in the current execution path; do not add a parallel
subplan scheduler or an isolation framework. See
[MoonCode runtime boundary](executable_book_runtime_boundary.md) and
[execution sandbox](EXECUTION_SANDBOX.md).
