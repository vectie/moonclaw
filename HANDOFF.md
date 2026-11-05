# MoonClaw Handoff

Read `AGENTS.md` and [documentation guide](docs/README.md) before changing
runtime behavior.

Work directly on `main`; do not create a branch unless the user requests one.

## Eight primitive contracts audit 2026-11-05

- Current responsibilities are process/thread, memory, filesystem, I/O,
  synchronization, fault tolerance, data model and compute engine. See
  the runtime boundary and MoonDesk design synthesis for per-interface
  inputs/outputs, logic, actual guarantees and sibling comparisons.
- Retired unused `PruneResult`, `calculate_pruning` and `prune_messages`,
  four direct package dependencies and eleven legacy-only tests. Context
  has one real compiler; don't restore a second in-place pruning API.
- External execution entry points acquire session gates; internal
  `*_under_runtime_gates` borrow them. The loop no longer accepts a Boolean
  deciding whether to reacquire ownership. Lifecycle, execution, journal
  and native file locks protect different resources and remain distinct.
- Parallel scheduling reads the existing policy, not a second tool-name
  allowlist. Resource reads retain canonical identity. Declared read-only
  result recall and MCP listing now qualify for ordinary batches.
- Work-step identity follows operation_id on the runtime path. Provider
  call IDs can repeat upstream; they are not cross-round execution keys.
  Existing tests cover reuse, ordered parallel recall and no effect replay.
  Work steps use item_id/command_id/event_id; removed duplicate aliases
  step_id/turn_id/evidence_ref. Top-level turn/message IDs remain.
- Uncertain-operation recovery uses the common execution constructor.
  No extra state machine, agent, store, model call or human step was added.
- Remaining limits: cooperative native file locks; process tools/external
  writers do not participate. Resume uses existing service start/turn retry
  or task controls, not a daemon-wide boot scanner. Internal Json and
  partial dependency provenance do not constitute a typed IR or full DAG.

- Validation: Claw native 1853/1853; identity/session 21/21; initial focused
  checks 43/43; Desk core JS 65/65 and UI 839/839; real producer/consumer
  probe passed. Info/fmt and interface diff reviewed. Production .mbt net
  -157, tests net -282. No UI layout/build or installed-app change; no live
  provider/performance qualification. Archive hashes remain unchanged.



## MoonCode Direction

Use [Executable book runtime boundary](docs/executable_book_runtime_boundary.md)
for the consolidated execution path: one primary
agent, autonomous completion, reused loop/journal/continuation/`finish`, and
deletion of duplicate mechanisms. No new runtime framework, permanent
Router/Worker team, universal human review, or old-protocol compatibility is
required.

The complete discussion is retained in the optional sibling MoonDesk checkout
at `docs/mooncode-discussion-2026-11-04/`. Do not combine superseded proposals
into additional implementation requirements.

The 2026-11-05 synthesis lives in optional sibling MoonDesk at
`docs/MOONCODE_AGENT_MACHINE_AND_DYNAMIC_GRAPH.md`. It consolidates system
primitives, data models, framework comparisons and runtime graph construction.
The minimal graph UI projects existing execution facts; complete dependency
analysis remains planned. Graphs never introduce another execution authority.

## Programmable single-agent path 2026-11-05

- Initial/follow-up share one model round. Ordinary tools and checkpoint share
  result assembly; consumers use the canonical result boundary.
- Completed operation IDs identify results; tool-call IDs join start/result.
  Same-millisecond parallel reads must never collapse or match by tool name.
- `read_result` reads only retained session results, including patch events.
  Compaction preserves exact or first/last references through repeated passes.
  It does not rerun effects or reconstruct output already truncated at execution.
- Work graph is a disposable canonical projection and uses existing UI cards
  and file navigation. It is not a scheduler, completion rule or new store.
- Known local chunks use existing shell/project scripts; tiny native edits are
  faster locally. Measurement: six read/write calls 4 ms; fixture-bridge .mbtx first
  512 ms / warm 204 ms (script also checked outputs; no model time/tokens; Degraded fixture,
  not a production MoonFort performance measurement).
  Do not claim end-to-end speedup or live deliverable-quality improvement.
- Validation: Claw native 1864/1864 + final projection focus 30/30; Desk
  native 1729/1729; core JS 65/65 + graph codec 3/3; UI 839/839; Node 24/24.
  Real producer/consumer probe, info/fmt and production UI build passed.
  Build 53.57 s; main chunk +4049 bytes vs baseline. Source production net
  +482/test +341; shared round/result consolidation alone net -61 production.
  Existing warnings remain; live-provider and installed-app qualification
  are not included. The historical archive remains unchanged.



## Current MoonCode Implementation

- Projection/Telemetry cleanup (2026-11-05): canonical `/watch` now lives in
  MoonClaw, using the existing exact watch contract. MoonDesk adapts metadata
  and keeps its typed decoder/navigation cancellation. Removed the unused typed
  resume projection and the desktop snapshot/raw-stream/snapshot relay.
- Watches wait on filesystem metadata and rebuild from the committed journal;
  turn projection uses a temporary command index. Rebuilds still read full
  history. Minimal graph UI shipped in the later five-step change; there is
  still no incremental projection cache or complete dependency graph.
- Planner usage/latency/retries attach to existing final planner events,
  including empty responses. Removed the synchronous exporter and old
  configured/effective compression counters. Usage projects from durable events,
  not compacted plans or repeated receipts. Reuse the daemon UUID for response
  observations: time alone is not a unique event identity. No extra append,
  model request, observer store, evaluation phase or confirmation was added.
- Preserve missing usage as unmeasured and missing prices as unpriced. Outer
  retries/request size do not measure every billable attempt or final provider
  HTTP body. Runtime errors/results and offline harness/replay remain facts,
  not another acceptance authority. Live outcome/cost baselines remain pending.
- Validation: Claw native 1862/1862; Desk native 1729/1729; core JS 65/65;
  UI watch/usage 108/108; producer/consumer probe passed. Info/fmt, whitespace
  and expected interface changes reviewed. Combined code/tests net -2046.
  The real restart fixture retains all six responses through two empty
  follow-ups and service restart, with one actual file write. 42 local links
  and 11 archive hashes checked. Existing warnings and installed-app/live
  qualification limits remain; runtime and desktop need the same watch contract.

- Legacy Goal and Goal Runtime were removed, including API/store/supervisor,
  public reducers, dual authority and dedicated old tests. Ordinary `finish`
  is the completion entry; there is no quality-trial or no-change protocol.
- Milestones are advisory and may reopen. Do not restore discovery counters,
  mutation quotas, prompt-phrase tests or mandatory all-done checkpoints.
- All checkpoint reasons share one writer with journal result references.
  Validate/hydrate durable checkpoints through
  `mooncode_runtime_continuation_for_command`; raw packets intentionally omit
  accumulated tool-result bodies.
- Tool positions checkpoint before effect, journal intent, and attach identity
  to the normal result event. Reuse committed results after restart; an intent
  without a result is unknown, not permission to replay an effect. A claim with
  no execution facts can safely start planning again.
- Keep live corrections as ordered task updates with a revision. Appending
  negative instructions to the original text triggered keyword-based coding
  inference and an endless finish-repair loop in the steering fixture.
- Check fingerprints cover touched files and declared check inputs only. They
  are not a dependency-complete snapshot or semantic acceptance proof.
- Checkpoint and operation intent now share one journal record. When resuming
  an interrupted safe read, reuse the committed checkpoint; do not append the
  same stable checkpoint ID with a new timestamp or payload.
- Completed checks survive an ordinary observation failure after successful
  recovery. Mutations, failed checks and unknown effects still invalidate them;
  rejecting optional progress or a finish proposal is not an executed effect.
- The nine-step executable-book lifecycle report and contract were removed.
  They marked ordinary sessions blocked for missing edits/review/packages and
  duplicated task completion. Keep canonical conversation/runtime receipts and
  explicit Book acceptance facts; do not restore the independent readiness test.
- Native initial and follow-up requests share one catalog. Keyword bundles,
  native `tool_search`, deferred receipt validation and their simulated
  benchmarks were deleted. Read-only subsets, explicit tool selection and MCP
  inventory/calls remain. Workers are absent from the default catalog.
- Empty follow-ups retain the claim and results for autonomous retry regardless
  of progress notes. Milestone predicates, `all_done` receipts and required
  checkpoint contracts were removed; advisory checkpoints inspect no evidence.
- The agent machine model maps existing execution, context, files, IO,
  synchronization and recovery; it introduces no new runtime layer. Every model
  shares one primary instruction: work top down until a change and its check are
  clear, act, verify and repair. Kimi's duplicate builder, keyword language
  primer and prompt-phrase tests were removed; provider transport stays separate.

## Tool boundary cleanup 2026-11-05

- The sibling synthesis's current module plan replaces the rejected generic
  phases 0–5. It maps Task/Execution/Context/Workspace/Tools/Journal/Completion/
  Projection/Telemetry to responsibilities, concrete removals and behavioral
  checks. Task/Completion/Execution are implemented; Tools/Workspace now have a
  first cleanup pass. Unchecked resource identity, ABI and isolation work remains
  pending. Retain actual authority, isolation and data integrity. The
  older ten-item checklist describes the previous tool-boundary cleanup.
- Pure execution properties and shell analysis now belong to
  `internal/mooncode_tools`, with no IO imports. Concurrency, instruction
  consumption, replay and local execution/validation are independent; the
  daemon still owns authorization, execution and durable facts.
- The Guardian shadow trial, old effect wrappers, unused shell-observation
  helper and test-only transcript counters were removed with their obsolete
  tests. Pure shell tests moved to their owning module; runtime tests retain
  actual process, authority, cancellation and recovery checks.
- A commit is an execution fact, not the end of the command's repair cycle.
  The command-wide post-commit seal and terminal-commit parser were removed.
  Keep commit identity/path capture and current input verification; do not
  reintroduce per-tool HEAD/tree/status subprocess checks or require another
  user turn to repair after a commit.
- Native suite passed 1917/1917. The pure module passed 17/17 with a clean
  module check; two sandbox/runtime commit tests passed, including same-command
  repair and rejection of changed inputs after validation. The real MoonDesk
  producer/consumer probe passed. `moon info`, formatting and whitespace checks
  passed; only the new internal module adds an interface, existing `.mbti`
  files are unchanged. Production `.mbt` net -623 lines; tests net -498.
- No new model round, approval phase, database or service was introduced.
  Existing repository warning debt and deployment/live-provider limitations
  remain; fixture results do not establish semantic delivery quality.

## Task Completion Execution cleanup 2026-11-05

- Task intent now reads explicit caller intent only; default requests use the
  full native catalog. English keyword/negation parsers, deterministic prompt
  preplanning helpers and the universal MoonBit/MoonTown skill gate were
  removed. Project instructions and applicable skill loading remain.
- Task input retains complete long requests and trailing constraints; prose
  markers and a fixed 12k limit no longer discard task text. Initial prompts
  avoid copying the same objective/request twice. Task updates copy their array
  so later corrections cannot rewrite an earlier revision.
- Completion verdict and evidence helpers moved from planner to the existing
  completion file. Explicit required checks, output paths and tracked input
  versions remain enforced. Keyword-derived tests, coding-tool quotas, generic
  post-error successful-action requirements and duplicate terminal scans were
  removed. A partial explicit batch without accepted finish retains artifacts
  but does not establish task completion; failed primitive commands remain failed.
- The model's batch is no longer replaced by a forced read after edit errors.
  Safe repeated observations and transient-check retries execute normally.
  Journal operation identities, completed-result reuse, uncertain-effect
  feedback, approval, cancellation, leases and resumable quanta remain.
- Native suite passed 1899/1899, focused recovery/control coverage 118/118,
  and final task/completion/repair/catalog/parallel-read checks 20/20. The real
  MoonDesk capability producer/consumer probe passed. Check, info, formatting
  and whitespace validation passed; existing `.mbti` files are unchanged.
  Production MoonBit net -1122 lines; tests net -1069. No new package, state
  machine, runtime service, model round or confirmation step was introduced.
- Full-suite execution exposed test interference: a test-only global append
  cache clear invalidated another async test's seeded cache. Tests now evict
  only their own canonical journal path; the unused global-clear helper was
  deleted. Keep the scan-count assertions; do not mask this race with retries.
- Default full schemas may cost more than the old four-tool chat subset; use
  explicit selection where needed. Long-input working projection remains a
  Context follow-up. Existing six daemon info warnings, release warning debt,
  live-provider and installed-app qualification limits remain.

## Tools Workspace cleanup 2026-11-05

- Removed command-word approval inference and planner-based exemptions.
  Explicit approval annotations always remain effective; normal execution
  binds the exact configured MoonFort capability without an extra human step.
- Removed global shell-authoring prohibitions and file-tool MoonBit manifest
  grammar checks. Project instructions and real compiler checks remain.
  Shell now has one execution entry and one shared preflight implementation.
- The pure policy exposes only parallel-read, after-skill and replay facts.
  Removed obsolete sensitive/install/overwrite/inline-authoring parsing and
  associated tests; retained actual read-only scheduling and check semantics.
- Unified single/multi-file diffs use one executor with file/hunk identity,
  fingerprints, prevalidation and existing rollback. Scope is parsed once;
  absolute in-book paths compare like relative paths. Whole-workspace scope
  skips the Git snapshot; narrow scope snapshot failure precedes execution.
- Authoring shells invalidate prior checks through the existing boundary.
  Receipt changed paths join tracked check inputs; the collector returns
  paths directly instead of constructing artificial before/after states.
- Do not mark the entire Workspace/Tools plan done. General ABI/schema
  convergence, canonical symlink identity, narrow/formatter snapshot cost
  and external/concurrent-write isolation remain unchecked. Current grants
  have no per-task writable-path field; snapshots are not transactions.

- Validation: final native 1892/1892; final completion/formatter/repair checks
  17/17; real MoonClaw producer → MoonDesk decoder probe passed. `moon info`
  and `moon fmt` passed; the only interface diff removes obsolete internal
  tool properties/functions. Six existing daemon warnings remain. Production
  `.mbt` net -568 lines; tests net -447. No new package/state machine, human
  approval step or model request. No desktop runtime/UI change or installed
  app/live-provider qualification. Full-workspace scope removes entire Git
  snapshots, but narrow scopes retain their existing O(worktree) cost.

## Tools ABI and Workspace identity follow-up 2026-11-05

- The cached runtime catalog now owns schemas and supported-name lookup.
  One validator covers model decoding, pre-approval calls and execution.
  Removed legacy request aliases and hidden patch verification execution;
  actual grants and result/event/provider contracts remain distinct.
- Both repositories removed the unused native command policy tables,
  tool sequences and result checklists. Capability fingerprints changed
  together; keep the real producer/consumer probe, not those phrase tests.
- Physical workspace paths now join scope, aliases, parallel-read identity,
  verification and command selectors. Check receipts bind actual paths;
  retargeting an alias to equal bytes still invalidates the earlier check.
- Native writes reuse OS locks, pinned Book resource comparisons and atomic
  sibling rename. Stable per-resource lock paths survive inode replacement;
  other files proceed. Optional expected_fingerprint supports stale writes.
  Rollback only compares/restores successfully committed patch members.
- Pitfalls: /var and /private/var aliases must agree in shell boundaries and
  argv; pre-approval schema checks prevent malformed calls waiting on humans.
  A scope snapshot lists dirty tracked files, not every tracked file: a clean
  missing baseline needs read-only HEAD content, not deletion or blind restore.
  Runtime lock metadata belongs to .moonsuite, excluded like product state.
- Limits: CAS retains the reused 16 MiB text-reader bound and preserves rwx,
  not inode/owner/xattrs or cross-file/power-loss transactions. Process tools
  do not participate in native file locks; non-cooperative writes and hostile
  parent replacement remain stronger-isolation work. No new package, state
  machine, model round, global workspace mutex or human confirmation.

- Validation: MoonClaw native 1890/1890; MoonDesk native 1733/1733;
  protocol-core JS 66/66; focused runtime/core 16/16 and boundaries 23/23;
  real producer → decoder probe passed. Info/fmt passed, with the existing
  six daemon warnings. 40 local links and 11 archive hashes checked.
- Production MoonBit net -1695 across both repos (-901 Claw, -794 Desk).
  Tests net +66 after replacing retired policy assertions with four actual
  boundary regressions. Moving the catalog is not counted as deletion.
  Interfaces remove 25 unused policy APIs, add the shared validator and
  Stat.mode, and replace unchecked Git restore with read-only HEAD lookup.
  No installed-app or live-provider qualification was performed.

## Validation 2026-11-04

- After sharing the primary-agent program, native check and the full native
  suite passed 1927/1927 (`--target native --strip -j 2 --warn-list -all`).
  Focused runtime/context/compaction/process tests passed 98/98. The quantum
  restart fixture now uses a Kimi model identifier through the shared builder;
  this is a local mock transport, not a live-provider quality measurement.
- The real MoonDesk producer/consumer probe passed. `moon info`, formatting and
  whitespace checks passed; interfaces are unchanged. Retained tests cover
  completion repair, stale checks, restart, uncertain effects and cancellation.
- This is fixture validation, not deployment or live-model delivery-quality
  qualification. MoonDesk's strict release gate still has existing warning
  debt; do not describe it as a warning-clean release.

## Documentation Pitfalls

- Context/Journal cleanup (2026-11-05): initial and follow-up requests share
  `mooncode_context.mbt` and the existing compiler by default. Remove fixed
  suffixes, shadow/active flags and overload-driven rewriting. Execution owns
  output caps; model results stay complete JSON until Context projects them.
- Recovery uses one `MoonCodeResumePoint` decoder for existing loop positions.
  Keep exact approval binding, `finish_rejected`, completed-operation reuse and
  unknown effects. Generated ID spelling and guidance text are not authority.
  Invalid checkpoint references must raise, not look like an absent checkpoint.
- Directory-sync success belongs to the existing append cache. Invalidate it
  before archive/restore/delete intent: rename can succeed before sync fails,
  and lifecycle reconciliation can then reopen the active path. File bytes are
  still synced on every append; first observation/cache rebuild syncs ancestors.
- Compaction is lossy. `read_result` now recalls retained session results by ID
  or lists compacted ranges; never recover omitted outputs by replaying effects.
  The current contract is in `docs/LONG_CONTEXT_COMPACTION.md`.
- Native suite: 1873/1873; real MoonDesk producer/consumer probe passed. Info,
  fmt and whitespace checks passed; public interfaces unchanged. The full
  repository still has existing warnings, and no live-provider/app or power-cut
  qualification was performed. Code and tests together net -1611 lines; 95
  lines of test-only parser helpers moved out of production, not deleted.

- Old Goal/journal diaries mixed intermediate and completed migration states;
  they were retired. Confirm current source rather than reusing their test counts.
- Context provenance is v2 only; the former v1 reader was removed.
- A milestone checkpoint does not discard the actual planner transcript.
- New initial contexts use the shared program. Resumed transcripts retain their
  captured system instructions; do not silently rewrite those during compaction.
- Session execution ownership is not a MoonBook-wide write lock. Fingerprints
  detect stale tracked inputs; do not claim transaction isolation across sessions
  or external editors, or infer remote non-execution from a timeout.
- Repeated empty follow-ups after rejected `finish` must preserve the retained
  `finish_rejected` flag. Resetting it made the next continuation invalid and
  raised `InvalidJournal`; the restart fixture now covers two empty responses.
- Runtime service/loop execution already has a cross-process session lease.
- Physical journal sequences are positive exact decimals; derived cursors may
  be zero. Neither bounded integer conversion nor payload shadowing is valid.
- Independent observers belong to explicit qualification, not every task's
  completion. Execution success does not by itself adopt accepted book truth.
