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

## Validation 2026-11-04

- After removing milestone-dependent recovery, native check and the full native
  suite passed 1929/1929 (`--target native --strip -j 2 --warn-list -all`).
  The existing restart fixture now covers repeated empty follow-ups after a
  rejected finish without any progress checkpoints, followed by valid delivery.
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
- Repeated empty follow-ups after rejected `finish` must preserve the retained
  `finish_rejected` flag. Resetting it made the next continuation invalid and
  raised `InvalidJournal`; the restart fixture now covers two empty responses.
- Runtime service/loop execution already has a cross-process session lease.
- Physical journal sequences are positive exact decimals; derived cursors may
  be zero. Neither bounded integer conversion nor payload shadowing is valid.
- Independent observers belong to explicit qualification, not every task's
  completion. Execution success does not by itself adopt accepted book truth.
