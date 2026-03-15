# Workspace And Memory

This document describes the expected behavior of dedicated run workspaces and memory.

## Workspace Roots

Expected behavior:

- the configured workspace root comes from `agents.defaults.workspace` in `moonclaw.json`
- MoonClaw ensures that workspace root exists
- the workspace runtime treats it as the default logical workspace for planning and job execution

## Per-Run Workspaces

Expected behavior for a top-level run:

- create a dedicated run workspace under:
  - `<workspace>/.moonclaw/job-workspaces/<run_id>`
- initialize a git repository there
- write run metadata
- project workspace files are materialized into that run workspace

Expected behavior for a subjob:

- create a nested sub-workspace under the parent run workspace
- preserve lineage to the parent run

## Git Behavior

Expected behavior:

- the run workspace has its own git repo
- MoonClaw records checkpoints on important execution transitions
- the git repo is for run-local history, not for replacing the main project repo

## Workspace Files

Expected behavior:

- `IDENTITY.md` reflects identity-shaped memories
- `ROUTINES.md` reflects routine-shaped memories
- `MEMORY.md` reflects broader inherited and run-local memory context

These files are materialized for the run workspace so the agent can work with concrete files instead of only in-memory state.

## Structured Memory

Expected behavior:

- structured memories are stored independently from artifacts
- memory search can return relevant prior notes
- planning and execution can use memory context
- successful jobs can automatically capture summary/report memories

## Manual Workspace Notes

Expected behavior:

- if a run edits `MEMORY.md`, the manual content can be synced back into structured memory
- this makes the workspace file layer and memory layer bidirectional instead of write-only

## Memory Scope

Expected behavior:

- memories can be scoped by workspace, channel, account, recipient, thread, and job context
- retrieval should prefer relevant scope instead of mixing everything together

## Inspecting Workspaces

Expected behavior:

- `/job-workspace <job_id|run_id>` should show:
  - workspace path
  - git status
  - recent commits

This is the operator-facing way to inspect what a run changed.
