# Executable Book Runtime Boundary

Last checked: 2026-07-15.

MoonClaw is the execution engine for executable MoonBooks. It owns agent,
task, session, and runtime concepts, but those concepts should remain platform
concepts rather than becoming the main MoonDesk product vocabulary.

## Standalone Project Rule

MoonClaw must run as its own checkout. It may expose HTTP/CLI/file contracts that other projects call, but it must not require adjacent MoonBook, MoonTown, or MoonDesk source checkouts to build, test, or start. Cross-project integration should use configured paths, published packages, or runtime protocols.

## MoonClaw Standalone Agent Runtime

MoonClaw standalone agent runtime is the reusable execution core for this system. It owns the shared runtime substrate: sessions, event logs, tool execution, cancellation, process lifecycle, model/tool loops, and bounded task jobs. MoonDesk, MoonTown, MoonBook tooling, a CLI, or a future standalone `mooncode` app may call it, but none of those clients should make MoonClaw a private implementation detail.

The shared runtime substrate does not mean one vague product protocol. MoonCode uses `/v1/code/*` for executable-book coding sessions. Generic automation uses `/v1/task*`. MoonWiki and book-review flows may call MoonClaw by protocol for bounded execution, but they should keep their own durable evidence and book-editing vocabulary.


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

MoonCode package turns also emit a MoonBook-shaped result sidecar using the
`moonbook.executable_event.v1` JSON contract. MoonClaw marks generated
executable artifacts as `review_required`; it can prove build/test/package
facts, but it does not promote them to accepted book truth.

Package verification must include the complete nearest MoonBit module, not
only files edited in the final turn. Inventories exclude build caches,
dependencies, generated portable output, and nested repositories. Structured
`moon_cmd` evidence may declare `expected_exit_code`; an observed expected
nonzero exit is accepted negative-path proof rather than a runtime failure.

The model loop is bounded for implementation quality: tool results are
compacted before they re-enter the transcript, implementation requests take
precedence over incidental “read” wording, repeated inspection must progress
to a mutation, and explicit paths outside the selected MoonBook are rejected.
These are reusable runtime controls and must not embed a domain answer.

## Executable Book Call Chain

```text
MoonDesk
  -> MoonCode or MoonWiki surface for a selected MoonBook
  -> MoonClaw runtime API
  -> MoonBook filesystem/artifact store
  -> MoonClaw events/results
  -> MoonDesk projection
  -> Bookkeeper/user review
```

For MoonCode, the target native API namespace is:

```text
/v1/code/capabilities
/v1/code/sessions
/v1/code/sessions/<id>/commands
/v1/code/sessions/<id>/turns
/v1/code/sessions/<id>/runtime-claim
/v1/code/sessions/<id>/runtime-turn
/v1/code/sessions/<id>/runtime-loop
/v1/code/sessions/<id>/runtime-service  (GET state, POST start)
/v1/code/sessions/<id>/runtime-events
/v1/code/sessions/<id>/stream
/v1/code/sessions/<id>/tool-exec
/v1/code/sessions/<id>/eval-report
/v1/code/sessions/<id>/package-result
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

`journal.jsonl` is the book-local, totally ordered session authority. Native
MoonCode runtime operations append command, claim, settlement, event, package,
and book-result records under `moonsuite-conversation-journal.v1`; receipts are
a record kind, not a separate store or runtime API.

MoonCode command intake uses the shared `mooncode/core` envelope contract.
`native_command_body_required_fields()` and
`native_command_body_supported_fields()` are the source of truth for top-level
command fields; MoonClaw validates `/v1/code/sessions/<id>/commands` against
that contract instead of maintaining a private route-specific allowlist.

Interactive clients submit through `/v1/code/sessions/<id>/turns`, which
combines durable command append and single-flight runtime-service start into one
MoonClaw-owned transaction. `/commands` remains the lower-level queue boundary
for diagnostic and explicitly orchestrated clients.

## Durable Conversation Controls

MoonClaw consumes MoonLib's `moonsuite-conversation-control.v1` contract. The
control plane is durable runtime state, not a second transcript:

- risky tool calls append a stable pending approval event to the owning command
- `approve_tool` and `reject_tool` commands append a durable decision and stay
  hidden from user/assistant chat
- the original runtime task waits for the decision and resumes with its model
  plan and tool-call context intact
- rejection records non-execution and allows the model to explain the outcome
- cancel names the claimed target command, rejects a stale target before
  interruption, then awaits the active task, terminates its child process, and
  appends command-scoped cancellation event and receipt

The canonical conversation projection reduces approval request and decision
events into one stable `approval` work step. Consumers render that list; they
must not merge raw events, create approval turns, or infer cancellation from a
local timer.

## Current Validation

Static doc/code inspection on 2026-07-15 found that MoonClaw has the right
runtime pieces: `cmd/daemon` contains MoonCode session binding, command
persistence, runtime-turn, runtime-loop, runtime-service, stream, tool-exec,
package-result, and eval-report slices; generic `/v1/task` routes still exist
for general jobs.

`/v1/code/*` is the current executable-book coding route family. Generic `/v1/task*` routes are intentionally separate and should not be used as the MoonCode implementation layer.

MoonCode result envelopes identify native coding output with `command_id` and
`result_id`. The nested MoonBook `BookResult` uses `result_id` directly, so the
coding result path remains independent from generic MoonClaw task identity.

## Documentation Rule

When updating MoonClaw docs:

- Use `MoonCode` or `live coding-agent`; avoid external protocol-copy language as product vocabulary.
- Describe `/v1/code/*` as the target coding runtime API.
- Keep `/v1/task*` only for generic background jobs.
- Do not say MoonDesk owns runtime, sessions, or task execution.
- Do not say MoonClaw owns durable book truth; it owns execution and proof.
