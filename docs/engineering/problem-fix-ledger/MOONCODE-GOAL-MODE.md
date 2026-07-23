# MoonCode goal mode: durable core reducer

Pure `mooncode/core` contracts and reducer only; daemon persistence/replay and API integration remain intentionally deferred. Caller-supplied integer timestamps make pure reducer replay deterministic. Event IDs provide idempotency. Requirements carry stable IDs, proof state, and evidence references; approvals remain caller-supplied references only. Public JSON projections are versioned and deliberately exclude approval/evidence details, internal reasoning, and secrets; this slice does not claim integration-level redaction coverage.

## Invariants

Creation is `Active`, and is `Runnable` only when the initial budget is not exactly exhausted; exact exhaustion produces `AwaitingBudget`. Completion requires a nonempty set of requirements, every requirement `Proven`, and nonempty evidence references on every proof. Evaluation stores its completed report and returns an active goal to runnable. Blocker observations use structured `BlockerIdentity` values, not fingerprints. Blocker correlation is scoped by `run_id` plus per-run ordinal: only the expected next ordinal in the current run advances the consecutive count, while stale run IDs or stale/wrong ordinals are exact no-ops. Matching observations block at the configured threshold; progress or `None` resets blocker accumulation. `Resume` starts a fresh run with a new `run_id`, clears the prior blocker, and isolates new observations from the resumed run's predecessor. Budget exhaustion remains active/awaiting-budget. `ContinuationAccepted` increments only continuation count; `TurnFinished` increments only the goal turn and applies blocker state. Duplicate event IDs are exact no-ops, including revision and time. Unknown requirement IDs and blocked/complete absorption are reducer invariants, but this ledger does not claim dedicated tests unless present in the suite.

## Problem/fix ledger

- An interrupted migration left a mixture of old four-arity and new six-arity blocker/event calls, producing broad compiler fallout. Completed the migration consistently across contracts, reducer call sites, and tests before addressing behavioral failures.
- Progress and `None` blocker observations failed to reset accumulated blocker state. Corrected reset handling and added focused regression coverage.
- Several MoonCode follow-up sessions failed or lost required tool capabilities. Recovery was bounded to the available MoonBook tools, with changes and validation resumed in a capable session.
- Initial correlation tests supplied incorrect per-run ordinals. Corrected them to use the expected ordinal sequence for each `run_id`.
- `assert_eq` requires `Show`, while several structured core values provide equality without a suitable `Show` implementation. Used boolean equality assertions for those values and retained `assert_eq` for showable scalar fields.
- Early duplicate-ID tests were vacuous because their events would have been no-ops even with distinct IDs. Reworked them so a distinct event would mutate state, making the duplicate-ID assertion meaningful.
- Generated `.mbti` interface output became stale during contract changes. Regenerated/formatted it from the current source and compiler view rather than treating stale output as authoritative.
- Repository formatting required semantic-no-op changes in `mooncode_persistence` and `protocol_wbtest`; those edits are formatter-only and do not extend this slice's behavior.
- The resumed-run regression now unwraps the second fresh blocker observation and asserts structured identity, count `2`, and correlation to `resumed.run_id`, in addition to remaining `Active`.
- The initial draft made a reconstructed `Goal` locally mutable and then assigned immutable record fields. Fixed by reconstructing a fresh immutable `Goal` for each event branch.
- The first reducer appended to event history through a mutable-looking intermediate. Fixed by copying `seen_ids` before append, preserving reducer purity and input ownership.
- The initial event model combined accepted continuation, finished goal turn, and blocker accounting. Split it into `ContinuationAccepted` and `TurnFinished` with independent counters.
- Evaluation incorrectly left the goal in `Evaluating`. `Evaluated` now records the completed report and returns runnable.
- Added caller-data-only approval waiting/settlement transitions; no approval reference is synthesized.

This slice changes and validates only the pure core and its documentation/tests. Daemon persistence, daemon replay, and API integration remain deferred and are not claimed here.
