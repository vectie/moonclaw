# Worktree And Subplan

This note defines the boundary between logical task decomposition and execution isolation.

## Core idea

- `subplan` is a runtime orchestration concept
- `worktree` is an execution-environment concept

They are related, but they are not the same thing.

## What a subplan is

A subplan is a child workflow created when a parent step is too broad, too complex, or should be decomposed before useful execution.

In MoonClaw, subplans belong to the job/runtime layer:

- [/Users/kq/Workspace/moonclaw/job/workflow_engine.mbt](/Users/kq/Workspace/moonclaw/job/workflow_engine.mbt)
- [/Users/kq/Workspace/moonclaw/job/analysis.mbt](/Users/kq/Workspace/moonclaw/job/analysis.mbt)
- [/Users/kq/Workspace/moonclaw/job/adaptive_policy.mbt](/Users/kq/Workspace/moonclaw/job/adaptive_policy.mbt)
- [/Users/kq/Workspace/moonclaw/job/adaptive_subplan.mbt](/Users/kq/Workspace/moonclaw/job/adaptive_subplan.mbt)

A subplan answers:

- should this task be split?
- what should the child tasks be?
- how should parent and child runs relate?

## What a worktree is

A worktree is a separate checked-out working copy of the same git repository.

A worktree belongs to the execution-isolation layer, not the planning layer.

A worktree answers:

- where should this task run?
- should edits be isolated from the main checkout?
- should this task get its own branch and filesystem state?

## Correct relationship

The correct relationship is:

1. a parent step runs
2. adaptive execution decides whether it needs a subplan
3. if a subplan is created, execution policy decides where that child task should run
4. one possible execution target is a git worktree

So:

- subplan decides logical decomposition
- worktree decides filesystem isolation

## Why they should stay separate

If worktree is mixed directly into the workflow engine, the runtime becomes harder to reason about.

If subplan is replaced by worktree, MoonClaw loses explicit task structure.

Keeping them separate preserves:

- clean orchestration semantics
- reusable execution backends
- simpler status, lineage, and resume logic

## Recommended architecture

### Job/runtime layer

Keep subplan logic here:

- [/Users/kq/Workspace/moonclaw/job/workflow_engine.mbt](/Users/kq/Workspace/moonclaw/job/workflow_engine.mbt)
- [/Users/kq/Workspace/moonclaw/job/adaptive_policy.mbt](/Users/kq/Workspace/moonclaw/job/adaptive_policy.mbt)
- [/Users/kq/Workspace/moonclaw/job/adaptive_subplan.mbt](/Users/kq/Workspace/moonclaw/job/adaptive_subplan.mbt)

This layer should remain responsible for:

- `completed / needs_input / needs_subplan`
- child workflow creation
- parent-child lineage
- waiting and resume

### Execution-isolation layer

Add worktree support here:

- [/Users/kq/Workspace/moonclaw/job/execution_isolation.mbt](/Users/kq/Workspace/moonclaw/job/execution_isolation.mbt)
- [/Users/kq/Workspace/moonclaw/internal/worktree/manager.mbt](/Users/kq/Workspace/moonclaw/internal/worktree/manager.mbt)
- [/Users/kq/Workspace/moonclaw/tools/enter_worktree/tool.mbt](/Users/kq/Workspace/moonclaw/tools/enter_worktree/tool.mbt)
- [/Users/kq/Workspace/moonclaw/tools/exit_worktree/tool.mbt](/Users/kq/Workspace/moonclaw/tools/exit_worktree/tool.mbt)

This layer should be responsible for:

- selecting shared workspace vs isolated worktree
- creating worktrees and branch names
- cleanup policy
- exposing worktree context to tools and child execution
- supporting execution-layer tools such as:
  - `delegate_run`
  - `enter_worktree`
  - `exit_worktree`

## Recommended control flow

1. parent step executes
2. adaptive layer returns `needs_subplan`
3. child workflow is created
4. execution isolation policy chooses:
   - shared workspace
   - run workspace
   - git worktree
   - remote target
5. child run starts using that execution target

The key boundary is:

- subplan creation happens before execution isolation selection

## Suggested future types

### `ExecutionIsolationMode`

- `shared_workspace`
- `run_workspace`
- `git_worktree`
- `remote_target`

### `ExecutionIsolationSpec`

- `mode`
- `cwd`
- `branch_name?`
- `source_repo_root?`
- `cleanup_policy?`

## Recommended policy

Default rules should be simple:

- pure analysis or document tasks: shared/run workspace
- code-edit tasks with possible conflicts: prefer worktree
- risky refactors or delegated coding branches: require worktree

This keeps worktree use purposeful instead of turning every child run into an isolated checkout.

## Summary

- subplan is about task structure
- worktree is about execution isolation
- a subplan may use a worktree, but it should not be defined by one
- the hook point is between child-plan creation and child execution
