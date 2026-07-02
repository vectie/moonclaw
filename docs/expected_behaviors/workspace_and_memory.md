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
  - `.moonsuite/products/moonclaw/jobs/<run_id>`
- initialize a git repository there
- write run metadata directly inside the run workspace
- keep the run workspace itself run-owned rather than copying workspace context files into it

Expected behavior for a subjob:

- create a nested sub-workspace under the parent run workspace at:
  - `<parent_run_workspace>/moonclaw-subjobs/<run_id>`
- preserve lineage to the parent run

## Git Behavior

Expected behavior:

- the run workspace has its own git repo
- MoonClaw records checkpoints on important execution transitions
- the git repo is for run-local history, not for replacing the main project repo

## Workspace Files

Expected behavior:

- workspace-owned markdown stays in the workspace where it changes over time
- run workspaces do not automatically copy `AGENTS.md`, `USER.md`, `IDENTITY.md`, `ROUTINES.md`, or `MEMORY.md`
- run workspaces should contain files created by the run itself plus internal run metadata

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

This only applies when a run explicitly creates `MEMORY.md` itself. MoonClaw no longer pre-populates that file in every run workspace.

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
