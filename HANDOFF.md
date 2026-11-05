# MoonClaw Handoff

Read `AGENTS.md` and [documentation guide](docs/README.md) before changing
runtime behavior.

Work directly on `main`; do not create a branch unless the user requests one.

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
Graph UI and complete dependency analysis remain planned; graphs should project
existing execution facts rather than introduce another execution authority.

## Current MoonCode Implementation

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

- The sibling synthesis contains phases 0–5 for remaining work, separately
  from the completed cleanup checklist. Recovery and compaction already exist;
  the proposed work consolidates their contracts/default paths. Dynamic graph
  UI and live-model/installed-app qualification remain outstanding.
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

- Old Goal/journal diaries mixed intermediate and completed migration states;
  they were retired. Confirm current source rather than reusing their test counts.
- Context provenance writes v2; v1 describes an existing reader path.
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
