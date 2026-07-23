# MoonCode goal mode: durable core reducer

**Original pure-core checkpoint:** Pure `mooncode/core` contracts and reducer only; daemon persistence/replay and API integration were intentionally deferred at that checkpoint. Durable daemon genesis/replay is now implemented; HTTP/controller integration remains deferred. Caller-supplied integer timestamps make pure reducer replay deterministic. Event IDs provide idempotency. Requirements carry stable IDs, proof state, and evidence references; approvals remain caller-supplied references only. Public JSON projections are versioned and deliberately exclude approval/evidence details, internal reasoning, and secrets; this slice does not claim integration-level redaction coverage.

## Invariants

Creation is `Active`, and is `Runnable` only when the initial budget is not exactly exhausted; exact exhaustion produces `AwaitingBudget`. Completion requires a nonempty set of requirements, every requirement `Proven`, and nonempty evidence references on every proof. Evaluation stores its completed report and returns an active goal to runnable. Blocker observations use structured `BlockerIdentity` values, not fingerprints. Blocker correlation is scoped by `run_id` plus per-run ordinal: only the expected next ordinal in the current run advances the consecutive count, while stale run IDs or stale/wrong ordinals are exact no-ops. Matching observations block at the configured threshold; progress or `None` resets blocker accumulation. `Resume` starts a fresh run with a new `run_id`, clears the prior blocker, and isolates new observations from the resumed run's predecessor. Budget exhaustion remains active/awaiting-budget. `ContinuationAccepted` increments only continuation count; `TurnFinished` increments only the goal turn and applies blocker state. Duplicate event IDs are exact no-ops, including revision and time. Unknown requirement IDs and blocked/complete absorption are reducer invariants, but this ledger does not claim dedicated tests unless present in the suite.

## 2026-07-24 — P1 replay-hardening checkpoint

This P1 slice hardens replay around strict positive integral journal sequences; exact genesis, budget, and requirement membership; canonical objective and requirement strings; and nonnegative genesis timestamps. Genesis and mutation replay now bind payload timestamps to the physical envelope `recorded_at`. The controller-owned independent native daemon check and test gates pass **210/210 tests (210 passed, 0 failed)**.

Incidents encountered during the slice included an invalid `Map.insert` test helper, missing `raise` signatures, repeated unchanged failing checks until the planner cap, a prohibited `/tmp` shell attempt, false completion at 199/206 with seven failures, inability to create a new file through the edit tool, repeated invalid `moon fmt` targets, and bounded-turn continuations. The fixes were exact continuation anchors, adding `created_at` to the self-validation envelope, appending tests to an existing whitebox file, and controller-owned independent check/test gates.

Atomic compare-and-append remains the next P1 item, followed by the supervisor lease/fence/checkpoint loop.

## Problem/fix ledger

- **Final independently re-audited atomic-journal checkpoint:** The checkpoint passed **220/220**; the paused approval turn was cancelled rather than approved, then recovered through an exact compiler-guided continuation.
- **Problem/Fix — mutable journal payload identity:** Computing identity in the locked callback fixes mutable `Json` aliasing when a caller changes a shared payload while waiting for the journal lock.
- **Durability boundary — journal namespace:** No portable public directory-fsync API exists, so the first record receives a full file sync while namespace crash durability remains explicitly unpromised.

- **Problem/Fix — prohibited Python source rewrite attempt:** A Python-based source rewrite was attempted despite the structured-edit-only boundary. Recovery used bounded structured edits only.
- **Problem/Fix — invalid `moon fmt` targeting and repeated compile recovery:** Invalid file targeting and repeated compile-recovery attempts obscured progress. Use valid repository formatting targets and preserve the exact compiler diagnostics for each recovery.
- **Problem/Fix — `expected_exit_code = 255` masked a compiler failure:** Treating exit 255 as expected allowed a failed compiler invocation to appear successful. Normal validation expects exit 0, and the controller-owned check/test gate runs independently.
- **Problem/Fix — bounded continuations a through h:** Continuations a through h recovered the slice to **217/217 tests passed** under the independent controller gate.
- **Problem/Fix — runtime receipt false-negative after passing tests:** The h turn/service ended in a failed runtime state even though its final `moon test` passed **217/217**. Keep test evidence separate from turn/service runtime receipt state so neither is inferred from the other.

- **Problem/Fix — MoonBit symlink signature:** A repair wrongly assumed the positional symlink link path was labeled `link_path`; native compiler errors 4085/4080 exposed the actual `target~`-plus-positional signature, and all three calls were restored.
- **Problem/Fix — zsh verification variable:** The first full-suite wrapper assigned zsh read-only parameter status and stopped after the tests; rerun with task_status, confirming the full daemon suite passed 176/176.

- **Problem/Fix — double-wrapped sessions root caused false absence:** The `goal_gate_dir` test helper passed `mooncode_sessions_root(root)` into `mooncode_session_dir_by_safe_id`, which applies the sessions-root transformation itself, so fixtures landed in a double-nested store and production falsely returned `GoalSessionAbsentOrMismatch`. Pass book `root` directly while retaining the safe session ID and `archived` label; the invalid-JSON fixture still proves the generic `GoalSessionCorrupt` path.

- **Problem/Fix — independent security/evidence audit:** Dot aliases and snapshot or active-directory symlinks could evade ordinary identity fixtures, while rejection tests did not independently prove filesystem non-mutation. In particular, the sanitizer derives `mooncode_safe_session_id("..") == "_"`, so derived-name checks cannot identify the raw parent-directory token; the production gate now rejects raw `session_id == "." || session_id == ".."` before/alongside its derived safe-component checks. The session gate and its tests are async; rejection coverage captures exact immediate directory entry counts and snapshot bytes, verifies journals remain absent using the production session-root and journal-path helpers, and includes absent-root dot aliases and symlink fixtures.

## 2026-07-24 — Strict goal-event codec and long-task runtime recovery

- **Problem/Fix — cap exhaustion after verified work:** A tool/planner cap could turn a run into `runtime-failed` even after the final check and test succeeded. Completion now inspects accumulated proof and classifies cap exhaustion separately from failed verification.
- **Problem/Fix — capability-unavailable completion:** Finish-only capability-unavailable turns became `runtime-completed` despite making no edits. Typed capability-unavailable outcomes remain retryable, and `finish` alone is not proof of completion.
- **Problem/Fix — stale MoonBit APIs:** Work used `TurnFinished.run_id` as a string, `GoalBlocker`, a five-argument `Evaluated`, `Json::Bool`, and incorrect `ValidatedProjection` count types. Current source and generated `.mbti` contracts, followed by compiler-guided recovery, corrected those assumptions.
- **Problem/Fix — path containment and cleanup:** A daemon API comment was changed on the wrong path and root artifacts were created. Exact cleanup removed only those changes; controller work now requires a path allowlist and diff review.
- **Problem/Fix — prohibited write provenance:** Perl, `printf`, Python, and `cat` shell writes occurred despite explicit prompts. Structured edit provenance must be enforced rather than inferred from instructions.
- **Problem/Fix — independent controller gate:** Worker `finish` was incorrectly treated as proof. The controller independently runs `moon info && moon fmt`, checks the diff, reviews generated `.mbti`, executes all-target checks and tests, and verifies artifact status.
- **Problem/Fix — concurrent verifier deadlock:** Orphaned concurrent `moon` verifiers held the build lock. The exact stale PIDs were terminated, then all gates were rerun serially.
- **Problem/Fix — journal mutation identity:** Mutation identity collisions were removed by canonicalizing identity as `event:<event_id>` and rejecting blank or padded IDs; focused journal tests pass 5/5 on native.
- **Problem/Fix — strict 14-variant codec:** The codec now strictly decodes and encodes all 14 variants. The focused codec file passes 42/42 on native, and the full core passes 89/89 on native, JavaScript, WebAssembly, and WebAssembly-GC after envelope and membership hardening. Total encoder round-trip is guaranteed only for decoder-valid events; the earlier 40-test result was a focused checkpoint, not the current full-core count.
- **P1 follow-up — golden encoder fixtures:** Golden encoder fixtures remain required compatibility locks and are not yet complete; no completion claim is made for them.

## Chronological internal-API ledger (`goal-api-ledger-doc-2635`)

[Detailed internal-API ledger](MOONCODE-GOAL-MODE-INTERNAL-API.md)

1. **Internal API scope established:** Goal-mode recovery needed an API-only view of durable ledger data that could distinguish committed records from an incomplete trailing write without broadening public projections or exposing internal approval/evidence material.
2. **Broad ledger inspection was not accepted:** Approval for a broad ledger `cat` was cancelled, and the attempted `grep` remained stuck. Neither operation is treated as implementation evidence or as permission to broaden file access.
3. **Security audit rejected the first behavior:** A newline-less final record was falsely treated as committed, and invalid UTF-8 was surfaced as an internal 500 response. Both outcomes violated the committed-prefix and input-classification contract.
4. **Canonical replay experiment cancelled and restored:** An attempted change to canonical replay introduced a regression. That attempt was cancelled, and canonical replay behavior was restored rather than coupling the new API to a changed replay path.
5. **API-only committed-prefix reader added:** A new internal raw reader now returns only the committed newline-terminated prefix for API use. A sole torn genesis record yields no committed record; when valid committed records are followed by a torn suffix, only the committed prefix is returned. Invalid UTF-8 is rejected as invalid ledger input instead of being mapped to HTTP 500.
6. **Verification expanded:** Tests cover a sole torn genesis, a committed sequence with a torn suffix, and invalid UTF-8. The complete daemon suite passes **189/189**.
7. **Deferred limitation preserved:** The reader remains an unlocked read with a probe/open time-of-check-to-time-of-use window. Eliminating that TOCTOU condition is explicitly deferred; this ledger does not claim locking, atomic probe-and-open, or concurrent-writer safety beyond committed-prefix parsing.

- **Problem/Fix — transient no-tools recovery:** A transient no-tools turn could only report the audit rather than apply it. The recovery performs the bounded fixture rewrite and records the security and evidence proof in executable async tests.

- **Problem/Fix — strict session gate recovery:** The first slice invented an async `@fs` API (`mkdtemp`, directory/file predicates, and manual cleanup), omitted the required `archived` label on session-store lookup, and attempted an invalid file-path formatting target. The current async gate resolves active and archived fixtures through `mooncode_session_dir_by_safe_id(..., archived=...)`, uses non-following `@fs.kind` checks to require an active `Directory` and a regular `session.json`, then reads it with `@fsx.read_file`, classifying present/read/stat failures as corrupt; the obsolete following exists probe was removed. Async tests use `@fsx.with_temporary_directory`, and formatting uses the repository-level `moon fmt` command without an invalid target argument.

- **Problem/Fix — scoped edits and lexical test assertions:** A broad mechanical replacement escaped the intended goal-API scope into `packtool/command_executor.mbt`, changing `@fs.chmod` to `@fsx.chmod`; diff review caught the spillover and restored the original token. Separately, a collision-test no-mutation assertion was inserted outside its lexical temporary-directory closure; native compilation caught the unbound variables, and the assertion was moved inside the closure.

- **Problem/Fix — goal API parser audit test compile failures:** The rejection helper attempted to rethrow without a declared error type, loop integers were passed where `Json` was required, and fixture destructuring used unsupported refutable `let ... else` forms. Unexpected parser errors now abort loudly, integer fixtures convert explicitly with `to_json()`, and object/array fixtures use exhaustive `match` expressions while preserving the isolated parser audit coverage.

- **Problem/Fix — four new-test compile errors:** The JSON fixture helper used a raising object guard, assigned a `String` where `Json` was required, constructed the read-only `Object` form, and the padded disk replay test passed an obsolete third argument. Match `Object(fields)`, copy it, assign `replacement.to_json()`, return `Json::object(copied)`, and call `mooncode_replay_goal(root, " session ")` with two arguments.

- **Coverage — fourth-audit goal-store boundaries:** Focused tests prove create-side core genesis failures (blank objective, negative limit, and empty requirements) normalize to exactly `InvalidGoalGenesis` before append; canonical requested/envelope/payload session and goal identities reject padding while retaining the canonical `record_id`; and padded durable replay rejects before path access, leaving the seeded torn canonical-journal sentinel bytes unchanged.

- **Problem/Fix — fourth-audit duplicate key and masked session fixture:** Create preflight emitted a duplicate JSON `record_id`, while the session-mismatch fixture omitted the canonical ID and failed before its intended guard. Retain only the derived canonical key and include it in the fixture.

- **Problem/Fix — durable create gate and cancelled repair turn:** The new `record_id` invariant exposed a preflight omission, leaving the focused gate at 12/13; adding the canonical preflight ID fixes it. A stalled repair turn was cancelled before this focused repair was completed.

- **Problem/Fix — noncanonical identity append-after-failure:** A failed validation path could still append an event carrying a noncanonical identity. Canonicalize and validate identity before any durable append, so rejection cannot mutate the journal.
- **Problem/Fix — reserved-ID replay-ordering hole:** The hole was in replay ordering: any event payload carrying `goal-genesis-v1` is now validated as genesis or rejected; append simply preserves the occupied stable ID.
- **Problem/Fix — genesis envelope/payload identity mismatch:** Replay previously ignored the journal envelope `record_id`, so a reserved `event:goal-genesis-v1` envelope with an ordinary or mutated payload could be skipped, while a valid genesis payload under `event:other` could be accepted. Replay now reads `record_id`, includes the reserved canonical envelope identity in candidate detection, and requires every recognized goal-genesis payload to use exactly the derived `event:goal-genesis-v1` identity. The exact replay-required subset therefore includes `record_kind`, `record_id`, `session_id`, and `payload`.
- **Problem/Fix — discarded envelope session:** Decoding accepted an envelope while dropping its session field. Preserve and validate the session so replay remains bound to the original envelope context.
- **Problem/Fix — fractional/saturating `Number.to_int`:** Direct numeric conversion could accept fractions or silently saturate out-of-range values. Validate NaN, integer range, and truncation equality before converting.
- **Problem/Fix — duplicate-first generic retry preservation:** Timestamp validation had been moved before duplicate lookup, changing generic retry behavior. It is now restored after duplicate lookup; this was not an overwrite issue.
- **Problem/Fix — later-timestamp idempotency:** Compare only canonical caller-controlled immutable intent (`id`, `session`, trimmed `objective`, `budget`, and normalized `requirements`), explicitly ignoring server timestamps and derived `Goal` state; never compare the full `Goal`.
- **Problem/Fix — unsupported `Double.is_infinite`:** The target lacked `Double.is_infinite`. Replace it with portable NaN, bounds, and truncation checks.
- **Problem/Fix — bulk replay replacement deleted disk wrapper:** A broad replay edit accidentally removed the disk-backed wrapper. Restore the wrapper and keep the replay repair scoped to its intended implementation.
- **Problem/Fix — false-positive test caught its own failure:** A negative test's catch block also caught the test's deliberate failure. Record a post-catch boolean and assert afterward.
- **Problem/Fix — transient no-tool turn:** One recovery turn had no usable tool invocation. Retry in the next capable turn and keep this process incident in the ledger rather than a test-file header.
- **Problem/Fix — wrong MoonCode fmt/test targets:** Initial formatting and test commands used incorrect targets. Re-run with the repository's valid MoonCode targets.
- **Problem/Fix — strict replay fixtures:** Fixtures now include the exact replay-required subset: record_kind, record_id, envelope session_id, and payload; pure replay intentionally does not claim a complete MoonLib envelope.
- Replay rejects noncanonical requested/envelope/payload session and goal_id before trimming/path access.
- Create-side new_goal failures normalize to InvalidGoalGenesis.
- The guard-placement regression rejected ordinary events and was fixed by applying envelope/payload guards only after goal-candidate detection.

- **Problem/Fix — wrong-file insertion and cleanup:** API-audit comments were accidentally inserted into `gateway/client/client_wbtest.mbt`, outside the goal-store scope. Restored that file exactly to `HEAD`; the production integrity work remains confined to the daemon goal store, journal, and this ledger.

- **Problem/Fix — genesis evidence JSON context:** Casting only `evidence` as `Json` left the surrounding nested requirements object inferred as String-valued, causing compilation to fail. Give the whole nested requirement object explicit `Json` context while keeping `evidence` as `Json::array([])`, a real empty JSON array, without weakening replay validation.

- **Problem/Fix:** A new physical `goal-event` record kind conflicted with the MoonLib v1 journal allowlist. Goal records now use the shared physical `event` lane, with logical `mooncode.goal.*` subtypes; replay ignores unrelated events and fails closed on unsupported goal subtypes.

- **Problem/Fix:** The newly added restored-state regression initially failed because `EvaluationFailed` matched `request.run_id` to `expected_run_id` but not to the current `goal.run_id`; require `request.run_id == goal.run_id`, making stale restored requests exact no-ops.

- An interrupted migration left a mixture of old four-arity and new six-arity blocker/event calls, producing broad compiler fallout. Completed the migration consistently across contracts, reducer call sites, and tests before addressing behavioral failures.
- Progress and `None` blocker observations failed to reset accumulated blocker state. Corrected reset handling and added focused regression coverage.
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

The original slice changed and validated only the pure core and its documentation/tests. The later durable genesis/replay slice is now implemented and claimed below; HTTP/controller integration remains deferred.

## Durable evaluation failure/backoff v1

- **Problem:** Evaluation failure retries need durable, replay-safe identity binding; generic resume must not bypass retry deadlines.
- **Initial false-completion incident:** This slice was initially reported complete while `evaluation_backoff_wbtest.mbt` still required formatting and the generated core interface had not yet been reviewed. Completion now requires formatting and interface verification in addition to passing behavior tests.
- **Fix:** Core goal state records evaluation id, run id, basis revision, evidence digest, attempt, category, and next retry timestamp. Failure and retry events are exact-match/idempotent transitions, while the active/non-blocked Resume path remains limited to AwaitingInput recovery; Blocked Resume remains supported, and EvaluationBackoff Resume is excluded.
- **Deferred:** Daemon persistence, daemon integration, and endpoints remain explicitly out of scope for this pure-core slice.

## Durable goal genesis/replay

- **Problem/Fix — explicit null optional limits:** Absent optional limits are intentionally emitted as explicit JSON `null`, and replay requires those keys; they are not omitted.
- **Problem/Fix — optional arg misuse:** Replay passed the expected goal id as an invented positional store argument; remove the unused store parameter and retain `expected_goal_id` only on pure replay winner validation.
- **Problem/Fix — invented test helper/Show assertion:** Early tests depended on a nonexistent helper and Show-based structured assertions; exercise the real create/journal APIs and use `assert_true` for Goal equality.
- **Problem/Fix — partial catches:** Goal-genesis rejection tests matched only `InvalidGoalGenesis`; add exhaustive fallback branches that fail on every unexpected error.
- **Deferred:** concurrency stress, HTTP/routes, event mutation, and controller integration remain explicitly outside this checkpoint.
- **Problem/Fix:** MoonBit rejects tuple destructuring in a `for` binding; iterate over `case` and destructure it with `let (payload, session) = case` inside the block.

- Cancellation recovery: narrowed reserved/create catches to `InvalidGoalGenesis`, retained the empty-journal invariant for noncanonical identities, and removed the redundant disk replay assertion. Added stable-ID retry coverage proving an omitted timestamp is a no-error duplicate and leaves one journal record.
- Verified checkpoint gate: 17/17 focused native tests pass; daemon suite 161/161 native tests pass, including the corrupt-existing-journal integration test.

- **Problem/Fix — padded replay sentinel alias:** The first sentinel fixture used the wrong package alias; `@pathx` fixes it, and unchanged torn bytes prove the padded replay was rejected before opening/repairing the journal. The first directory creation omitted recursive parent creation and caused 15/16; `recursive=true` fixed it.

- **Problem/Fix — concrete integration fixture compile errors:** The corrupt-existing-journal test used obsolete `@fsx.mkdir` and positional/converted `journal_record` arguments, causing misleading `with_temporary_directory` arity and unbound-variable cascades; replace it with `@fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)`, contextual `recorded_at=123`, and explicit `payload=payload`.

- Problem/Fix — existing-journal fail-closed preflight: create previously appended before replaying an existing corrupt journal; it now replays existing durable state before mutation and returns idempotent/conflict without append when a winner exists. Canonical concurrent creates remain reconciled by append_once/post-replay. Explicit limitation: preflight read and append are not one atomic lock transaction, so a concurrent corrupt writer between them is deferred. The new integration test proves exact bytes and one-record count unchanged on rejection.

- **Problem/Fix — goal-api-two-json-fixes validation bookkeeping:** The repair produced compiling code, and the canonical focused command `moon test cmd/daemon/mooncode_goal_api_wbtest.mbt --target native` passed 6/6; the bounded MoonCode turn was nevertheless marked failed because its final redundant command combined incompatible `-p`/path/filter selectors and exited 2. Disregard that invalid redundant invocation and rerun the canonical exact-file test plus the native check/full daemon suite externally; results were 6/6 and 167/167.

- Strict goal API parser: exact nested schemas now reject unknown/missing fields; normalized construction prevents client-supplied usage, proof state, or evidence.

## Unterminated escaped-string goal API fixture

- **Problem:** The invalid-protocol daemon test used a malformed, unterminated escaped JSON string, preventing the focused test file from parsing.
- **Fix:** Replaced the string parsing loop with a contextual multiline `Json` object literal using protocol `other`, canonical fields, explicit null budget limits, and one valid requirement.

- **Problem/Fix — goal API durable-session authorization could falsely accept synthesized snapshots (read-only gate slice):** General binding/session loaders may create state or synthesize snapshots for missing or invalid files, and safe filesystem IDs may collide. Added a private, read-only gate that validates canonical nonblank query values, checks an active directory and real regular `session.json`, parses that file directly, and requires exact kind/protocol/owner/session/root identity. It returns only the canonical root and value-free typed invalid-query, absent-or-mismatch, or corrupt errors. Focused temporary-filesystem whitebox tests cover exact success, malformed queries, archived-only and missing files, corrupt JSON, every identity mismatch, collision resistance, and rejection non-creation. No route, handler, capability, binding, or general loader was changed.
- **Recovery — API gate filesystem coverage:** Added dot-path, symlink, and exact no-mutation snapshot coverage while preserving the six strict parser tests.


### Gate audit recovery: direct symlink APIs

A bounded follow-up turn was exhausted searching for `read_link`, which was unnecessary. The recovery uses direct `symlink`, non-following `kind`, `exists`, and immediate directory-entry counts. Combined dangling active-directory and dangling `session.json` evidence now verifies exact `GoalSessionCorrupt`, no journal, absent targets, retained symlink kinds, and no containing-directory mutation.

## Recovery note: false codec completion

A prior recovery incorrectly marked the goal-event codec checkpoint complete after
adding only commentary. No JSON encoder/decoder or codec tests existed. The
checkpoint remains open until the strict supported-variant codec, reducer
evidence canonicalization, tests, formatting, native check, and focused native
tests all pass.

## False completion: `Json::null` constructor mismatch

A previous turn reported completion without editing the source, while an independent check still found the line 98 type mismatch at `None => Json::null`. The proof-gated fix changed the affected option-to-JSON branches in `mooncode/core/goal_event_codec.mbt` to invoke the constructor as `None => Json::null()` and withheld completion until validation succeeded.

Proof: `moon fmt mooncode/core/goal_event_codec.mbt && moon check mooncode/core --target native --warn-list +73 && moon test mooncode/core --target native` exited successfully, with all 40 tests passing.
