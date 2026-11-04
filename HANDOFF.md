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

## Single-Agent Consolidation 2026-11-04

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
- Final validation: native suite 1953/1953, including daemon 606/606. Interfaces
  were regenerated and formatting/diff whitespace checks passed. Removed public
  interfaces belong to Goal and duplicate review/proof vocabulary. This is
  fixture-backed validation, not live-model delivery-quality qualification.

## Documentation Pitfalls

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

## Continued Cleanup Validation

- Native suite passed 1950/1950 after removing obsolete lifecycle/net-mutation
  policy tests. Coverage includes restarting after a claim or a committed read
  intent, uncertain effects, recovered observations and failed required checks.
- MoonDesk's local producer/consumer probe passed against this checkout.
  Interfaces were regenerated; the only additional public API removal is the
  retired executable-book lifecycle declaration. No new runtime package,
  database, agent role or approval step was added.

- Old Goal/journal diaries mixed intermediate and completed migration states;
  they were retired. Confirm current source rather than reusing their test counts.
- Context provenance writes v2; v1 describes an existing reader path.
- A milestone checkpoint does not discard the actual planner transcript.
- Runtime service/loop execution already has a cross-process session lease.
- Physical journal sequences are positive exact decimals; derived cursors may
  be zero. Neither bounded integer conversion nor payload shadowing is valid.
- Independent observers belong to explicit qualification, not every task's
  completion. Execution success does not by itself adopt accepted book truth.

## Pre-refactor Checkpoint 2026-11-04

- Existing runtime, Book resources/skills, saved-diff work, and documentation
  cleanup are preserved before the planned MoonCode consolidation.
- Native check passed with existing warning debt. Full native tests passed
  2306/2306; saved-diff JavaScript tests passed 7/7. Interfaces were regenerated
  and formatting completed. This does not claim a warning-clean release.
- Use the GitHub remote for the main baseline; the older Gitee origin was
  behind the already-published GitHub main when this checkpoint was prepared.
