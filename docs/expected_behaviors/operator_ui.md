# Operator UI

This document describes the expected behavior of MoonClaw's Rabbita operator UI at `/ui`.

## Ordinary Journey

The first viewport names one next action from current durable state and shows:

```text
Ask → Plan → Review → Run → Inspect
```

The operator UI has four main surfaces:

- `Home`
  next action, progress, local/remote summary and recovery guidance
- `Work`
  outcome request, evidence attachments, conversation, plan preview and
  promotion
- `Runs`
  local job expansion, workflow progress, artifacts, memory, and run workspace inspection
- `Remote`
  remote-agent control for ACP targets, sessions, runs, stdout/stderr, and remote run history

Runtime/provider vocabulary belongs in progressive disclosure. A primary
screen should state the operator's goal, current stage, one dominant action,
the durable outcome, and a plain-language recovery path when blocked.

## Local Job Expectations

The local job lane should:

- show job expansion as a tree plus timeline
- highlight the active step and newly created nodes
- expose artifacts, workspace state, memory, and linked remote activity
- show remote handoff entries in the local timeline when ACP work was triggered from the local run
- surface final run `report.md` and `result.json` as clickable cards even when they only exist as workspace files
- aggregate starter-document inputs into one operator-facing `Starter Docs` card instead of many low-level artifact cards
- open textual reports and artifacts in a full-screen editor-style surface
- let the run canvas expand into a full-screen layout that hides the side panes

## ACP Expectations

The ACP lane should:

- show targets, sessions, and runs as distinct remote-agent entities
- let the operator attach, detach, reset, run, and cancel where appropriate
- stream remote stdout/stderr activity while a run is active
- keep per-session run history visible
- show local-origin linkage when an ACP session or run came from a local job context

ACP export behavior:

- `Export` on a run should download one ACP run transcript
- `Export Session` on a session should download session metadata plus run history
- `Export Timeline` on a session should download the full ACP session event stream

## Mixed Overview Expectations

The mixed overview should not flatten local jobs and ACP into one fake runtime.

It should instead:

- show local and remote execution as parallel lanes
- show recorded local->remote handoffs when exact linkage exists
- show explicit and inferred links separately
- allow the operator to focus one lineage and scope related mixed panels to it

When a lineage is focused:

- `Explicit Links` should scope to that lineage only
- `Inferred Links` should scope to that lineage only
- the focused-lineage summary should expose direct jumps into both the local and ACP lanes

Mixed export behavior:

- `Export` on the focused lineage should download the lineage transcript
- `Export Case` on the focused lineage should download a combined case artifact containing:
  - local run transcript
  - focused lineage transcript
  - linked ACP session timeline transcripts that can be resolved from the current ACP snapshot

## Gateway Expectations

The gateway should serve the built operator UI bundle from:

- `/ui`

The operator UI should remain usable through gateway-hosted static serving after the frontend bundle is built.

Keyboard users can skip directly to the workspace, every visible control has
a 44-pixel target and focus indicator, asynchronous outcomes are announced,
and reduced-motion preferences disable nonessential animation.
