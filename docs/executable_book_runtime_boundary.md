# Executable Book Runtime Boundary

MoonCode is MoonClaw's coding role. The normal direction is one primary agent
working from the user's goal through implementation, checks, repair, and
delivery. The runtime owns execution facts; the agent owns reasoning and
planning. This is a responsibility split, not a permanent Router/Worker team.

## Agent Machine

These names describe existing runtime responsibilities; they do not add an
operating system, agent role or state machine.

| Responsibility | Interface and logic | Owned guarantee and limit |
| --- | --- | --- |
| Process / Thread | A claimed prompt/package command is the logical task. `mooncode_start_runtime_service` owns the main coroutine; `mooncode_runtime_loop_execute` acquires session ownership; `mooncode_runtime_turn_execute_under_runtime_gates` runs one execution quantum. Safe tool children belong to its TaskGroup and join in source order. | Session is a Book-bound queue/journal container, not an OS process. A model round is not a thread. Cancellation follows owned tasks; there is no independent address space or persistent program stack. |
| Memory | `mooncode_runtime_turn_compile_context(command,messages,tools,window,output_tokens)` returns messages/metrics. `Pruner::compile_messages` is the sole projection algorithm. `read_result` reads retained session output by reference or first/last range. | Budgeted working set, durable facts and source files have distinct owners. Projection is lossy; original truncated stdout and old file versions are not recreated. No extra model round or mandatory retrieval stage. |
| Filesystem | `mooncode_workspace_path(book_root,path)` resolves identity. `mooncode_workspace_replace(root,absolute,expected,content)` compares the observed contents under a stable file lock and stages a sibling rename. | Native file tools share per-resource conditional writes. This is not MVCC, a multi-file transaction or a lock observed by arbitrary shell/external writers. |
| I/O | Catalog schema → `mooncode_execute_tool_call_in_runtime` → bound grant/executor where required → canonical result → `mooncode_tool_execution` envelope/event → journal and model/UI adapters. Provider transport owns model protocol. | Arguments, authorization, execution outcome and loop control are separate contracts. A successful function/MCP call does not prove permissions, idempotency or task completion. Repairable errors go to the same agent. |
| Synchronization | Lifecycle shared/exclusive gate protects session lifecycle; execution lease owns session execution; journal/session lock orders claims/appends; file lock protects one canonical path; TaskGroup joins children. | External execution entry points acquire gates; internal `*_under_runtime_gates` calls borrow them. No runtime boolean chooses whether to reacquire ownership. Different resource locks are not a universal Book mutex or cross-service clock. |
| Fault tolerance | Checkpoint/intent → `MoonCodeResumePoint` → `mooncode_runtime_operation_recovery` → retained result, safe read or unknown-outcome error. Results use the same execution constructor. | Committed results are reused; uncommitted effects are reconciled. Current restart entry is service start/task control/turn retry, not a daemon-wide boot scan of every Book. No arbitrary script stack recovery or universal exactly-once. |
| Data model | session_id scopes queue/log/lease; command_id + task_revision identify task; operation_id identifies `(command,step,index)`; tool_call_id pairs protocol calls/results while operation_id joins runtime start/result across rounds; event_id identifies retained evidence; journal sequence is an exact decimal cursor. | Identities, content versions and ordered commit positions are different. Work steps retain item_id/command_id/event_id without duplicate step_id/turn_id/evidence_ref aliases. Most command/result structures are still Json, not a fully typed IR or complete dependency graph. |
| Compute engine | Context → model round → tool batch → observations → next round/finish. Policy declares parallel-read/replay/skill barriers; resource reads use canonical identity and other declared read-only calls use exact arguments. Known local programs run through existing shell/project tooling. | Whole tasks are interpreted incrementally. Ordinary mixed/mutating batches retain source order. Work graph is a materialized view; it neither schedules nor accepts work. No universal computation cache, static task DAG, or new language runtime. |

Source owners: [service](../cmd/daemon/mooncode_runtime_service.mbt),
[loop](../cmd/daemon/mooncode_runtime_loop.mbt),
[context](../cmd/daemon/mooncode_context.mbt),
[compiler](../internal/context_pruner/pruner.mbt),
[workspace](../cmd/daemon/mooncode_workspace.mbt),
[catalog](../cmd/daemon/mooncode_tool_catalog.mbt),
[executor](../cmd/daemon/mooncode_tools.mbt),
[result](../cmd/daemon/mooncode_tool_execution.mbt),
[journal](../cmd/daemon/mooncode_session_journal.mbt),
[continuation](../cmd/daemon/mooncode_runtime_continuation.mbt),
[operation recovery](../cmd/daemon/mooncode_runtime_operations.mbt),
[batch](../cmd/daemon/mooncode_parallel_reads.mbt),
[effects](../internal/mooncode_tools/policy.mbt),
[graph](../cmd/daemon/mooncode_conversation_graph.mbt).

These are responsibility contracts within existing packages, not eight new
layers. File names are organizational: MoonBit files in one package share
definitions. The daemon still contains substantial orchestration and Json
records; it is not a fully typed compiler kernel. Native file synchronization
is cooperative. Fingerprints cover touched/declared check inputs, not all
semantic dependencies. Journal order is local commit order; remote timeouts
do not prove non-execution. Snapshot rebuilds/read_result still scan history.


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
The native runtime no longer inserts a MoonBit/MoonTown-specific dynamic skill
gate. Default requests receive the same tool catalog; only explicit read-only
mode or caller-selected tools narrow it. Prompt vocabulary does not select
tools or invent mandatory tests.

Task construction retains the complete user request, including long plans and
trailing constraints. It does not cut input at prose markers or a fixed 12k
limit. The initial prompt uses one task representation; a separate original
request is included when an explicitly supplied objective differs. Ordered
corrections retain the same contract and create a new revision without mutating
the earlier revision's update array. Context-window projection remains a
separate responsibility.

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

## Workspace

File tools do not enforce a programming language's manifest grammar; project
instructions, skills and the actual compiler own those requirements. Shell
redirection, in-place editing and script generation may execute under the
configured grant. Shell text path checks and narrow-scope Git restrictions
remain; removing authoring preferences does not remove those boundaries.

Single-file and multi-file unified diffs use one patchset implementation:
resolve each file, load its content, validate every selected hunk, then apply.
Single-file results retain their file/hunk identity and fingerprints while
also carrying the shared files array. Before/after replacements remain a
separate edit syntax, not a second unified-diff executor. Shell calls that cannot be classified as
observations invalidate earlier checks using the existing verification
boundary; actual receipt `changed_paths` joins subsequent tracked inputs.
This adds no execution gate or model round. The old path collector no longer
constructs artificial before/after states just to extract their paths.

`mooncode_workspace.mbt` owns physical resource resolution and conditional
writes. Symlink aliases inside the book share a path identity; escaping or
dangling links are rejected. New files resolve through the nearest existing
parent. Scope, read-batch identity, verification inputs and process selectors
reuse this resolver. Verification binds both the actual path and its content.
Task scope is decoded once per execution. No scope or `scope=["."]` skips the task-scope
Git snapshot; an explicit formatter selector retains its own containment.
A failed narrow-scope snapshot refuses execution before effects occur.

Narrow process scope and selective `moon fmt` still use working-tree
snapshots and restore checks. The current grant has no per-task writable-path
field, so these are retained rather than replaced with an unverified claim
of backend isolation. Scope recovery now uses the same conditional writes
as native tools rather than unchecked Git restore or unconditional overwrite.
A clean tracked baseline is read from Git, then compared before restoration.
This protects changes after observation; snapshots cannot attribute every
change made by an external process while the command itself is running.

Native writes take stable OS locks keyed by canonical book/path, then compare
the observed content before replacing a staged sibling file. Locks survive
inode replacement and coordinate sessions without serializing unrelated
files. Read returns a fingerprint; write accepts it optionally. Edit retains
old-text matching. Patches validate all members before writing and reject
duplicate aliases. Rollback touches only committed members and refuses to
overwrite a subsequent edit; unresolved partial recovery stays explicit.

These are per-file conditional updates, not cross-file transactions or
universal exactly-once effects. The existing Book resource reader caps CAS
text comparisons at 16 MiB. Writes preserve observed rwx bits; owner, inode
and xattrs are not preserved guarantees. Atomic rename is not an fsync or
power-loss guarantee. A hard crash can leave an orphan staging sibling;
unknown effects still use existing journal reconciliation, not blind replay. Non-cooperating shell/editor changes can still race the
final comparison, and hostile parent-directory replacement needs a stronger
descriptor-relative write boundary. Raw process isolation remains MoonFort's
configured responsibility; no global workspace mutex was added.

## Tools And Human Decisions

The existing model-facing schemas now live in `mooncode_tool_catalog.mbt`
and are constructed once. Supported-name lookup, model decoding, pre-approval
validation and final execution consume that catalog and one pure recursive
validator. Malformed arguments return errors before scope IO or effects;
explicit approval cannot turn malformed arguments into executable input.
Opaque plans/approval annotations remain outside the provider ABI. Exact
grants are still checked at execution, and provider results use the existing
result/event envelope. The Moon command plan and executor share physical argv.

Old request-envelope aliases and the hidden patch verification executor were
removed. Checks use ordinary explicit tool calls and journal receipts. Both
repositories dropped the unused native command policy/checklist tables from
their capability contract, keeping actual owner/protocol/endpoint metadata.
They cannot silently reintroduce review or keyword gates as a second ABI.

Pure tool-call properties, argument validation and shell analysis live in `internal/mooncode_tools`.
The daemon composes them with parameter validation, runtime authorization,
providers, journal writes and execution. This module performs no IO and does
not grant permissions. It owns concurrency, skill-consumption order and
interrupted-call replay; the obsolete local-operation/local-validation
approval properties were deleted. Unknown calls remain serial and cannot be
replayed merely because their parameters match.

File and process tools stay within their declared scope and authorization.
Process execution requires the configured MoonFort route; missing configuration
does not select a host-shell fallback. Direct `/tool-exec` currently returns 503.
See [Execution sandbox](EXECUTION_SANDBOX.md).

Command names, shell mutability, snapshot updates and `planner` labels do not
create or waive human approval. Only an explicit `requires_approval` or
`approval=operator` annotation requests it. Otherwise the runtime binds the
exact call to capabilities from trusted MoonFort configuration; a model's
approval/safety claim cannot supply a grant. Configuration absence or mismatch
refuses execution. Explicit approval requests bind the exact operation and parameters. Recovery uses the
stored approved operation; rejection records non-execution and returns feedback
to the agent. Timeout remains pending. Cancellation targets the active command
and must reach its process before a cancellation result is claimed.

Ordinary errors should be repaired by the same agent when possible. Human
intervention is for real authority or decision gaps. Explicit book adoption or
product acceptance is separate from engineering completion and delivery;
ordinary tasks do not acquire a mandatory independent reviewer.

The Guardian shadow trial and its duplicate approval observations were removed.
The actual authorization and sandbox checks remain. Git commit records the
created revision and paths; it no longer seals the whole command or has to be
the final shell operation. The same agent can repair, format and recheck within
the current authorized task. Completion still checks current task/input
versions. Removing the per-call post-commit guard also removes its repeated
HEAD, tree and worktree subprocess queries.

## Completion And Verification

The legacy Goal reducer and the separate Goal Runtime API, genesis, projection
and supervisor were removed. The separate nine-step lifecycle report, which
required edits, review and packaging for every session, was also removed.
There is no Goal compatibility reader, dual authority, quality-trial gate or
independent desktop acceptance reducer. Existing loop, journal, sandbox and
continuation remain the execution path. All continuation
reasons share one writer and reference completed results instead of copying
their accumulated output.

The [Context/Journal contract](LONG_CONTEXT_COMPACTION.md) uses one default
window-budgeted compiler for initial and follow-up requests. Fixed message
suffixes, active/shadow experiments and overload-driven transcript rewriting
were removed. Tool execution owns output limits; Context owns model projection.
Canonical task revisions and the newest exchange survive projection. Omitted
history is lossy; retained result references and compacted first/last ranges
can be read through the current-session `read_result` tool, without execution.

Canonical watch now belongs to MoonClaw. The desktop reuses the existing codec
and metadata adapter; it does not download raw event bodies to advance a cursor
or construct another watch projection. Exact cursors use journal positions,
not event counts. The unused typed-resume projection was removed. Existing work
steps/evidence supply the minimal work graph of batches, calls, file references
and check inputs. No graph store, scheduler or model call is introduced.

Planner observations attach bounded metrics to existing events, including empty
responses. Conversation usage sums those durable facts rather than rereading
compacted historical plans or overwriting usage from receipts. The synchronous
exporter and duplicate compression-policy counters were removed. Collection
adds no network wait, journal round, model role or task acceptance decision.

Continuation validation is one typed position decoder at the recovery boundary,
not another state machine. Broken result references raise an explicit journal
error. Existing append-cache entries retain successful directory sync so cached
appends sync file bytes only; cache rebuild and real directory mutations retain
conservative directory synchronization. The whole-result aggregate digest and
obsolete Goal journal special cases were removed.

Completion rules and result-evidence helpers live together in
`mooncode_runtime_completion.mbt`, separate from model transport and schema
construction. The turn reuses one terminal verdict rather than independently
selecting another completion policy from the request text or planner mode.

An explicit `task_contract.required_checks` entry names `id`, `tool` (`shell`
or `moon_cmd`), exact `command` and `cwd`. Successful native sandbox receipts
after the latest mutation, failed check or uncertain effect must match those
entries. An optional observation failure does not require an unrelated
successful tool action before finish and does not invalidate checks of unchanged
inputs; rejected finish or progress metadata is not an execution failure. Optional
`input_paths` identify files relevant to those checks. Typed check/test/build
results also support normal coding verification; arbitrary successful shell
observations do not make a package verified. The runtime does not infer extra
completion requirements from English keywords, coding-tool categories or
mutation quotas. The primary agent remains responsible for understanding and
following the user's and project's semantic requirements.

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
a file edit. The agent chooses how to recover from an edit mismatch or failed
check; the runtime no longer replaces its proposed batch with a forced read.
Repeated safe reads and transient-check retries execute normally. Existing
evidence remains available as guidance, not a read/retry prohibition. Journal
operation identities still prevent replaying an already committed invocation,
and interrupted effects without results remain unknown.

An explicit batch that ends without an accepted finish retains its real
artifact/result references but does not establish task completion. Primitive
commands such as run-tests still report a failed operation as failure; an
unrelated finish cannot erase that command's failure.

Ordinary completion does not require packaging, an isolated snapshot or human
acceptance. Native harness evaluation reports its own scope and does not treat
caller-supplied review or success claims as deliverable acceptance.

The complete discussion and final plan are retained in the optional sibling
[MoonDesk archive](../../moondesk/docs/mooncode-discussion-2026-11-04/README.md).
The later [agent machine and dynamic graph synthesis](../../moondesk/docs/MOONCODE_AGENT_MACHINE_AND_DYNAMIC_GRAPH.md)
records the OS/compiler/database/dataflow analysis and task-driven interpreter
design. Minimal dynamic graph presentation is implemented; complete dependency
analysis, automatic invalidation and recomputation remain outside its guarantees.
The runtime and the summary above remain usable without that checkout.
The synthesis includes the concrete simplification checklist and verification
evidence for this cleanup; it does not turn runtime checks into new user gates.

## Validation

Use focused native tests for the changed boundary, then the repository release
gate described in [Responsibility and testability](RESPONSIBILITY_AND_TESTABILITY.md).
Cover incomplete finish recovery, changed task instructions, stale verification,
approval rejection, cancellation, and crash reconciliation. Compare deliverable
quality, user intervention, rework, latency, and total cost.

[Harness regression](HARNESS_REGRESSION_GATES.md) describes existing test
fixtures; [replay](HARNESS_REPLAY.md) compares recorded observations. Fixture
success and dated test counts do not establish current live delivery quality.
