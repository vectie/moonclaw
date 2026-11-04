# MoonClaw Handoff

Read `AGENTS.md` and [documentation guide](docs/README.md) before changing
runtime behavior.

## MoonCode Direction

Use [Executable book runtime boundary](docs/executable_book_runtime_boundary.md)
for current behavior and the approved, pending simplification: one primary
agent, autonomous completion, reused loop/journal/continuation/`finish`, and
deletion of duplicate mechanisms. No new runtime framework, permanent
Router/Worker team, universal human review, or old-protocol compatibility is
required.

The complete discussion is retained in the optional sibling MoonDesk checkout
at `docs/mooncode-discussion-2026-11-04/`. Do not combine superseded proposals
into additional implementation requirements.

## Documentation Pitfalls

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
