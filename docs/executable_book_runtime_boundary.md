# Executable Book Runtime Boundary

MoonCode is MoonClaw's coding role. The normal direction is one primary agent
working from the user's goal through implementation, checks, repair, and
delivery. The runtime owns execution facts; the agent owns reasoning and
planning. This is a responsibility split, not a permanent Router/Worker team.

## Agent Machine

These names describe existing runtime responsibilities; they do not add an
operating system, agent role or state machine.

| Computer concept | MoonCode equivalent | Existing implementation |
| --- | --- | --- |
| Process | One claimed command executing a task with its scope, results and resumable position. A session contains the command queue and journal. | Runtime turn, claims and continuation |
| Thread | One primary model/tool control flow within that execution. Independent safe reads may run as child async tasks and join in call order. | Planner loop and parallel reads |
| Memory | The bounded model-facing working context: task, observations, progress and skill receipts. Durable results remain reloadable through journal references. | Context projection, compaction and continuation hydration |
| Filesystem | The selected MoonBook's actual files and deliverables. Journal records describe execution; they do not replace the workspace or prove its current contents. | Book-relative file tools and existing artifact references |
| IO | Authorized tool calls and results; user input, steering and controls enter through the existing command/event paths. | Tool executor, sandbox, command queue and stream |
| Synchronization | One session execution owner, locked ordered journal writes, dependency-aware tool batches and version checks for verification inputs. | Session lease, journal locks and input fingerprints |
| Fault tolerance | Recover the saved position, reuse committed results, repeat safe observations and reconcile unknown effects. | Journal-backed continuation and operation intent/result identity |

The session lease does not lock every MoonBook file across sessions or external
editors. Serial writes in one loop are not global workspace transactions.
Fingerprints detect stale verification for tracked inputs; they do not provide
complete dependency isolation. Remote tool timeouts do not prove non-execution.
Journal order establishes local committed order, not a universal clock across
external services. Preserve these limits when extending concurrency.

## Programming The Agent

The program is the user's task interpreted under project instructions and
applicable installed skills. Tools supply executable operations. Retrieved
content and tool output remain observations, not new authority.

The shared primary-agent instruction implements this working method:

```text
identify the observable result and relevant checks
locate the existing implementation
decompose until the next change and its verification are clear
act; inspect further only to resolve a concrete uncertainty
verify, repair and continue until the complete request is satisfied
finish with the deliverable and concise verification
```

Planning and execution alternate inside the existing loop. Simple tasks may
reach an executable action immediately. Progress is expressed as observable
results; optional plans do not require user confirmation. There is one initial
message builder for every model, including Kimi. Provider-specific transport
handling remains separate from the working method. Kimi now receives the same
installed-skill catalog as other models. This adds no model call or planner
phase; prompt cleanup alone does not establish token or latency improvements.
Language details come from project instructions, installed skills and
compiler/tool feedback, rather than a second keyword-selected language primer.

## Standalone Project Rule

MoonClaw must run as its own checkout. Building, testing, and starting it must
not require adjacent MoonDesk, MoonBook, or MoonTown checkouts. Clients use
published packages, configured paths, and runtime protocols.

## MoonClaw Standalone Agent Runtime

MoonClaw standalone agent runtime provides the shared runtime substrate:
model/tool loops, session journals, authorization, cancellation, process
lifecycle, and recovery. MoonDesk presents input, progress, results, and
necessary decisions. MoonBook and Bookkeeper own accepted book truth.

MoonCode should not be implemented as generic task chat. Coding sessions use
`/v1/code/*`; generic task/job APIs remain separate. Existing job, coordination,
and worker capabilities are optional execution facilities, not mandatory stages
of every coding task.

## Current Execution

The current native path is:

```text
turns -> durable command queue -> runtime service
      -> runtime turn -> model/tool results -> continuation or terminal receipt
      -> canonical conversation and artifact references
```

- `POST /v1/code/sessions/<id>/turns` appends a command and starts or reuses
  execution. Append and startup are recoverable, not one crash-atomic action.
- Runtime claim, loop, and service execution coordinate through a stable
  per-session execution lease. A competing owner receives HTTP 409.
- Positive `planner_max_steps` values are resumable scheduling quanta. Exhaustion
  persists the next position and completed results rather than proving failure
  or completion. The default value is zero.
- One command carries the task definition: identity/revision, objective,
  constraints, outputs and required checks. Live user updates revise that task
  and remain in journal-backed context after restart.
- `finish` is the completion entry point. Repairable missing checks return to
  the same agent. An already-satisfied request uses ordinary `finish` with its
  findings; it does not require an edit or a separate no-change protocol.
- Checkpoints save advisory progress. Milestones may be changed or reopened;
  counts, all-done checkpoints and consumed mutations do not prove completion.
- Automatic service execution continues resumable planner quanta and transient
  interruptions. Explicit service limits remain caller-controlled bounds.
- An empty model follow-up retains the claim and completed results for another
  planner request, whether progress notes are absent, active or done. Recovery
  does not require a milestone or an all-done checkpoint. The same `finish`
  boundary still checks the current task and necessary verification facts.
- Completed tool results and the actual model transcript survive milestone
  checkpoints. Context projection is handled separately; a checkpoint does not
  itself justify discarding source observations.

The API details are in the [daemon reference](../cmd/daemon/README.md).
Current capabilities and source types, rather than old migration logs, define
the available routes and fields.

## Durable Facts And Recovery

The selected workspace resolves the MoonClaw product home through MoonLib:

```text
<moonclaw-product-home>/mooncode/sessions/<session-id>/
  journal.jsonl
  session.json
```

The journal is authoritative. The snapshot and in-memory bindings are
replaceable projections. Continuations retain the plan, resume position,
approval binding, and completed-result references.

Journal sequences are exact canonical decimal strings. Append checks the
committed prefix, identity conflicts, and exact successor under stable locks;
only a torn final suffix is repaired. Physical record sequences are positive;
derived empty/read cursors may be zero. File data is synchronized, with
directory synchronization on supported platforms. These are ordinary
process/crash guarantees, not strongest sudden-power-loss qualification.

Each serial tool position records its checkpoint and execution intent in one
journal append. Its ordinary tool-result event carries the operation identity
and compact execution metadata;
the output is stored once. Recovery reuses that committed result. If an effect
has an intent but no result, the agent receives an unknown-outcome error and
must inspect the workspace or backend receipt before choosing another action.
Read-only local observations may be repeated. A claim interrupted before any
execution can start planning again. This is not universal exactly-once execution.

## Tools And Human Decisions

File and process tools stay within their declared scope and authorization.
Process execution requires the configured MoonFort route; missing configuration
does not select a host-shell fallback. Direct `/tool-exec` currently returns 503.
See [Execution sandbox](EXECUTION_SANDBOX.md).

Approval requests bind the exact operation and parameters. Recovery uses the
stored approved operation; rejection records non-execution and returns feedback
to the agent. Timeout remains pending. Cancellation targets the active command
and must reach its process before a cancellation result is claimed.

Ordinary errors should be repaired by the same agent when possible. Human
intervention is for real authority or decision gaps. Explicit book adoption or
product acceptance is separate from engineering completion and delivery;
ordinary tasks do not acquire a mandatory independent reviewer.

## Completion And Verification

The legacy Goal reducer and the separate Goal Runtime API, genesis, projection
and supervisor were removed. The separate nine-step lifecycle report, which
required edits, review and packaging for every session, was also removed.
There is no Goal compatibility reader, dual authority, quality-trial gate or
independent desktop acceptance reducer. Existing loop, journal, sandbox and
continuation remain the execution path. All continuation
reasons share one writer and reference completed results instead of copying
their accumulated output.

An explicit `task_contract.required_checks` entry names `id`, `tool` (`shell`
or `moon_cmd`), exact `command` and `cwd`. Successful native sandbox receipts
after the latest mutation, failed check or uncertain effect must match those
entries. A recovered failed observation does not invalidate checks of unchanged
inputs; rejected finish or progress metadata is not an execution failure. Optional
`input_paths` identify files relevant to those checks. Typed check/test/build
results also support normal coding verification; arbitrary successful shell
observations do not make a package verified. Existing task-intent inference is
still a fallback when callers do not provide a typed task intent.

Checks capture content fingerprints for files touched by this task and declared
check inputs. `finish` checks those fingerprints and the task revision again,
and checks existence for declared `outputs` with a `path`. This is scoped
provenance, not a complete dependency graph or workspace snapshot. The agent
still owns semantic quality, adequate check selection, rendered UI validation
and whether an uncertain external effect has been reconciled.

Serial execution combines checkpoint and intent in one synchronized append
before a tool effect, followed by its ordinary result event. Recovery reuses an
already committed checkpoint instead of rewriting its stable identity.
Fingerprint cost scales with touched and declared input files, rather than all
workspace files. The regression suite covers execution behavior and observable
metrics; it does not establish live-provider latency or delivery-quality
improvements.

Native tools use one catalog for initial and follow-up requests; the
keyword-selected bundle flag, native `tool_search` and receipt-driven schema
expansion have been removed. Default coding capabilities remain available
without another discovery turn. Read-only selection, explicit tool lists and
the existing MCP tool inventory/call path remain. The default planner exposes
no worker tools. Invalid, unknown and truncated
tool calls return errors for repair; the runtime does not infer another tool
name or split concatenated arguments. There is no discovery counter that forces
a file edit. Repeating an immediately failed verification requests diagnosis;
subsequent observation can justify retry without manufacturing a mutation.

Ordinary completion does not require packaging, an isolated snapshot or human
acceptance. Native harness evaluation reports its own scope and does not treat
caller-supplied review or success claims as deliverable acceptance.

The complete discussion and final plan are retained in the optional sibling
[MoonDesk archive](../../moondesk/docs/mooncode-discussion-2026-11-04/README.md).
The later [agent machine and dynamic graph synthesis](../../moondesk/docs/MOONCODE_AGENT_MACHINE_AND_DYNAMIC_GRAPH.md)
records the OS/compiler/database/dataflow analysis and task-driven interpreter
design. Dynamic graph presentation and complete dependency analysis are not
implemented runtime guarantees.
The runtime and the summary above remain usable without that checkout.

## Validation

Use focused native tests for the changed boundary, then the repository release
gate described in [Responsibility and testability](RESPONSIBILITY_AND_TESTABILITY.md).
Cover incomplete finish recovery, changed task instructions, stale verification,
approval rejection, cancellation, and crash reconciliation. Compare deliverable
quality, user intervention, rework, latency, and total cost.

[Harness regression](HARNESS_REGRESSION_GATES.md) describes existing test
fixtures; [replay](HARNESS_REPLAY.md) compares recorded observations. Fixture
success and dated test counts do not establish current live delivery quality.
