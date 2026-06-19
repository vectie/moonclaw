# Executable Book Runtime Boundary

Last checked: 2026-06-18.

MoonClaw is the execution engine for executable MoonBooks. It owns agent,
task, session, and runtime concepts, but those concepts should remain platform
concepts rather than becoming the main Moondesk product vocabulary.

## Standalone Project Rule

MoonClaw must run as its own checkout. It may expose HTTP/CLI/file contracts that other projects call, but it must not require adjacent MoonBook, Moontown, or Moondesk source checkouts to build, test, or start. Cross-project integration should use configured paths, published packages, or runtime protocols.

## Ownership

| Concept | MoonClaw responsibility |
| --- | --- |
| Agent | Model/tool actor that plans, calls tools, observes results, and emits output. |
| Runtime | Execution substrate: tool dispatcher, event stream, cancellation, durable loop, process/service lifecycle. |
| Session | Durable interactive conversation or code session, especially for MoonCode. |
| Task | Bounded executable job for background or automation work. |
| Code session | Interactive executable-book coding workspace backed by MoonClaw runtime primitives. |

MoonClaw does not own MoonBook truth. It may write proposals, sidecars, diffs,
run artifacts, package proof, and review receipts into a selected MoonBook, but
Bookkeeper/MoonBook acceptance decides what becomes durable book knowledge or
code.

## Executable Book Call Chain

```text
Moondesk
  -> MoonCode or MoonWiki surface for a selected MoonBook
  -> MoonClaw runtime API
  -> MoonBook filesystem/artifact store
  -> MoonClaw events/results
  -> Moondesk projection
  -> Bookkeeper/user review
```

For MoonCode, the target native API namespace is:

```text
/v1/code/capabilities
/v1/code/sessions
/v1/code/sessions/<id>/commands
/v1/code/sessions/<id>/runtime-turn
/v1/code/sessions/<id>/runtime-loop
/v1/code/sessions/<id>/runtime-service
/v1/code/sessions/<id>/stream
/v1/code/sessions/<id>/tool-exec
```

Generic tasks remain separate and valid for background jobs:

```text
/v1/tasks
/v1/task/<id>
/v1/task/<id>/message
/v1/task/<id>/cancel
```

Rule: MoonCode should not be implemented as generic task chat. It should use
code-session/runtime contracts that can run tools, edit files, stream proof,
package executable artifacts, and resume from durable session sidecars.

## Current Validation

Static doc/code inspection on 2026-06-18 found that MoonClaw has the right
runtime pieces: `cmd/daemon` contains MoonCode session binding, command
persistence, runtime-turn, runtime-loop, runtime-service, stream, tool-exec,
package-result, and eval-report slices; generic `/v1/task` routes still exist
for general jobs.

`/v1/code/*` is the current executable-book coding route family. Generic `/v1/task*` routes are intentionally separate and should not be used as the MoonCode implementation layer.

## Documentation Rule

When updating MoonClaw docs:

- Use `MoonCode-style` or `Codex-style`; avoid external protocol-copy language as product vocabulary.
- Describe `/v1/code/*` as the target coding runtime API.
- Keep `/v1/task*` only for generic background jobs.
- Do not say Moondesk owns runtime, sessions, or task execution.
- Do not say MoonClaw owns durable book truth; it owns execution and proof.
