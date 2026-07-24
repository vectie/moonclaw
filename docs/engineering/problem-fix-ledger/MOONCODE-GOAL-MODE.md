# MoonCode goal mode: durable core reducer

## Validation trial problem: orphaned Moon lock

A focused decoder-test receipt falsely reported expected status 0 after its `moon` process was killed while blocked on an orphaned `_build/.moon-lock`. The controller isolated the generated orphan lock inode and reran the exact focused validation using a fresh generated lock path. The fix is to treat killed or lock-blocked commands as failed/inconclusive rather than successful, record the actual process outcome, and rerun the exact command after lock isolation.

> Command 005 recovery is in progress: controller/parallel audit identified that stored-event encoding must carry the exact `mooncode.goal.runtime.event.v1` kind and that constructor validation must cover every event variant. The decoder boundary is strict genesis-only JSON (exact keys/types/constants, canonical identities/text, checked nonnegative Int64 time, lowercase SHA-256, reconstruction and digest verification); store, HTTP, supervisor, legacy goal behavior, and aggregate caps remain out of scope.

**Original pure-core checkpoint:** Pure `mooncode/core` contracts and reducer only; daemon persistence/replay and API integration were intentionally deferred at that checkpoint. Durable genesis replay and the GET/PUT genesis endpoint are now wired; automatic controller/event replay remain deferred. Caller-supplied integer timestamps make pure reducer replay deterministic. Event IDs provide idempotency. Requirements carry stable IDs, proof state, and evidence references; approvals remain caller-supplied references only. Public JSON projections are versioned and deliberately exclude approval/evidence details, internal reasoning, and secrets; this slice does not claim integration-level redaction coverage.

## Invariants

Creation is `Active`, and is `Runnable` only when the initial budget is not exactly exhausted; exact exhaustion produces `AwaitingBudget`. Completion requires a nonempty set of requirements, every requirement `Proven`, and nonempty evidence references on every proof. Evaluation stores its completed report and returns an active goal to runnable. Blocker observations use structured `BlockerIdentity` values, not fingerprints. Blocker correlation is scoped by `run_id` plus per-run ordinal: only the expected next ordinal in the current run advances the consecutive count, while stale run IDs or stale/wrong ordinals are exact no-ops. Matching observations block at the configured threshold; progress or `None` resets blocker accumulation. `Resume` starts a fresh run with a new `run_id`, clears the prior blocker, and isolates new observations from the resumed run's predecessor. Budget exhaustion remains active/awaiting-budget. `ContinuationAccepted` increments only continuation count; `TurnFinished` increments only the goal turn and applies blocker state. Duplicate event IDs are exact no-ops, including revision and time. Unknown requirement IDs and blocked/complete absorption are reducer invariants, but this ledger does not claim dedicated tests unless present in the suite.

## Unbounded runtime-contract slice

`mooncode-goal-runtime.v1` is an additive pure-core state machine alongside the existing genesis/checkpoint contracts and bounded `mooncode.v1` runtime. It permits any number of explicit continuation and checkpoint events until the planner explicitly reports `Achieved` or `Blocked`, or an operator explicitly reports `Cancelled`. Provider timeout, empty output, no-progress pauses, and counters remain nonterminal observations. Stable event and operation IDs make replay idempotent, and terminal settlement is absorbing.

The two observed **hard-eight failures** were (1) an eight-turn/continuation ceiling settling work that still had a valid next action, and (2) an eight-unit execution/time quantum being promoted from an individual operation guard into an aggregate goal-completion deadline. Both failures confused bounded execution quanta with bounded goal solvability. The fix retains per-operation timeout/output resource policy so one tool invocation cannot run forever or emit unbounded data, while omitting—and rejecting—aggregate token, turn, wall-time, LOC, and deadline fields. Goal completion therefore has no arbitrary aggregate bound; safety remains local to each operation.

This slice intentionally does not add daemon scheduling or HTTP behavior.

## First persistence slice: strict daemon-private codec

**Exact boundary:** this slice adds only the daemon-private typed codec and whitebox tests for `mooncode-goal-runtime.v1`. It does not add a disk store, HTTP routes, supervisor/controller behavior, legacy Goal/GoalBudget changes, or core changes. Genesis semantics are independent of the legacy aggregate contract and contain only protocol, contract, session/goal identity, objective, and ordered criteria. Runtime journal integration must later retain MoonLib's supported physical `event` record kind and distinguish these records by their logical `mooncode.goal.runtime.*.v1` kind; `goal-runtime` is not a physical record kind.

- **Problem — retry identity was vulnerable to recording time:** Including `recorded_at` or a stable record ID in semantic hashing makes a response-lost retry at a later time appear to be different work. **Fix:** hash fixed-order semantic JSON only; exclude timestamp, digest, and stable ID, and verify the full lowercase SHA-256 digest on decode.
- **Problem — permissive persistence decoding hides schema drift:** defaulting readers and partial object matching silently accept misspellings, aggregate aliases, and future fields. **Fix:** the codec boundary uses exact recursive allowlists, checked integers, canonical unpadded identities, and core-equivalent decision validation before reconstructing reducer events.
- **Problem — legacy aggregate limits can leak into unbounded runtime genesis:** budget, turn/token/time/step/iteration/operation/LOC/deadline fields would reintroduce false terminal behavior. **Fix:** genesis uses only the exact v1 semantic fields and rejects aggregate completion fields at every relevant nesting level; operation policy remains positive without arbitrary maxima.

## Problem/fix ledger

- **Planner exhaustion falsely appeared terminal:** This clean recovery turn exhausted the legacy eight planner steps with one remaining test failure, proving the aggregate step bound can falsely terminate repairable work. Continuation resumed in a fresh command; the goal contract must never treat command/step exhaustion as terminal.

- **Problem/Fix — MoonBit symlink signature:** A repair wrongly assumed the positional symlink link path was labeled `link_path`; native compiler errors 4085/4080 exposed the actual `target~`-plus-positional signature, and all three calls were restored.
- **Problem/Fix — zsh verification variable:** The first full-suite wrapper assigned zsh read-only parameter status and stopped after the tests; rerun with task_status, confirming the full daemon suite passed 176/176.

- **Problem/Fix — double-wrapped sessions root caused false absence:** The `goal_gate_dir` test helper passed `mooncode_sessions_root(root)` into `mooncode_session_dir_by_safe_id`, which applies the sessions-root transformation itself, so fixtures landed in a double-nested store and production falsely returned `GoalSessionAbsentOrMismatch`. Pass book `root` directly while retaining the safe session ID and `archived` label; the invalid-JSON fixture still proves the generic `GoalSessionCorrupt` path.

- **Problem/Fix — independent security/evidence audit:** Dot aliases and snapshot or active-directory symlinks could evade ordinary identity fixtures, while rejection tests did not independently prove filesystem non-mutation. In particular, the sanitizer derives `mooncode_safe_session_id("..") == "_"`, so derived-name checks cannot identify the raw parent-directory token; the production gate now rejects raw `session_id == "." || session_id == ".."` before/alongside its derived safe-component checks. The session gate and its tests are async; rejection coverage captures exact immediate directory entry counts and snapshot bytes, verifies journals remain absent using the production session-root and journal-path helpers, and includes absent-root dot aliases and symlink fixtures.

- **HTTP recovery verification and remaining boundary:** Controller verification passed 192/192 daemon native tests and 3/3 focused HTTP seam tests, with `moon check` reporting 0 errors and formatting/diff checks clean. The route/body seam helpers are not the actual `Daemon::serve`/socket path; real socket and restart end-to-end coverage remains required.

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

## HTTP/controller recovery checkpoint

- **Problem/Fix — malformed-JSON assertion:** The focused HTTP test used a brittle Debug/Show snapshot (`Err("invalid_json")`) that rendered as `Err(invalid_json)`. Replace the snapshot with direct equality so the test proves the exact `Err("invalid_json")` contract without depending on display formatting.
- **Problem/Fix — ledger overwrite and recovery:** A prior ledger write replaced this committed 127-line history with a 19-line file (10 additions and 118 deletions). Restore the complete committed ledger from `HEAD`, then append this recovery checkpoint so all prior engineering history remains intact.

## Producer-neutral comparator checkpoint

Agreement and independent acceptance are separate outcomes: matching producer reports do not by themselves establish acceptance. Semantic evidence comparison ignores producer-local evidence IDs and compares meaningful evidence content instead. Controller basis validation rejects blank and empty bases. Checkpoint comparison traverses the sorted union of epoch/key pairs, preserving right-only checkpoints and detecting regressions that a left-only cadence would miss.

Problems met and fixes:

- The tool-call cap left compile/test work incomplete; validation was resumed incrementally.
- A stale session invented an obsolete `GoalCheckpoint` API; work was corrected against the current contracts.
- Invalid tuple-loop syntax was caught by the compiler and repaired.
- An old left-only cadence test failed after correct union semantics were introduced; it was updated for right-only checkpoint preservation and regression detection.
- Capability-unavailable turns made no edits.
- A failed broad-validation experiment was rolled back and replaced with incremental minimal validation.

Proof at this checkpoint: independent all-target core checks pass, and 54/54 tests pass on native, JavaScript, Wasm, and Wasm-GC. A warn-list `+73` run currently reports unnecessary-annotation warnings but zero errors.

- **Command 001 recovery — Array API:** The initial runtime slice used nonexistent `Array.concat`; repaired with `copy()` plus `push()`, matching `goal_reducer.mbt`.
- **Command 001 recovery — deprecated derive:** `Show` derives emitted deprecation diagnostics; replaced with `Debug`, while status-shape tests now inspect canonical JSON object keys rather than debug text.
- **Command 001 recovery — failed tests:** Two tests failed during the bounded attempt; contract validation and canonical status serialization were strengthened before rerunning native verification.
- **Command 001 recovery — forbidden redirect:** An attempted `/tmp` redirect violated the MoonBook boundary; subsequent commands keep all paths and output inside the MoonBook/tool capture.
- **Command 001 recovery — planner exhaustion:** The bounded planner exhausted before compiler repairs were applied; recovery made the requested implementation mutation first and retained the pure-core/no-daemon boundary.


### Command 002 recovery note

Command 002 reached step 8 and exhausted its execution allowance before formatting. Its recorded pre-recovery result was 60/60 core tests passing with check/info passing; formatting and the remaining runtime-contract hardening cases were deferred to this recovery pass.

- **Problem/Fix — blank runtime-event payloads (64/64 native core tests):** `OperationAccepted`, `CheckpointAccepted`, and `Cancelled` previously recorded a nonblank event ID before accepting a whitespace-only operation ID, checkpoint ID, or cancellation reason. The reducer now returns the original state before recording the event, making blank identifiers and payloads exact no-ops while preserving unbounded aggregate progress and per-operation resource guards.
- **Problem/Fix — command 003 false green:** Command 003 used a shell pipeline without fail-fast behavior; later successful cleanup masked the earlier 63/64 core-test failure. Validation now uses fail-fast sequencing so any failed stage remains visible and stops the command.

## command-005 — goal runtime v1 completion
The legacy eight-step planner exhausted before validation. Final audit fixes enforce canonical identities and detached terminal payloads while retaining externally nonconstructible state with safe accessors. The aggregate-name helper is only a diagnostic denylist; strict exact-allowlist decoder enforcement belongs to the next persistence adapter. Persistence, HTTP, and supervisor remain deferred.

- **Problem/Fix — command 007 masked compile failure:** The shell lacked `set -e`, so a successful trailing command masked the compile failure; verification now starts with strict failure propagation.
- **Problem/Fix — command 008 unsafe broad patch:** The broad patch was rejected, and `replace_all` corrupted a scoped identifier; the repair uses a cohesive, scoped edit.
- **Problem/Fix — command 009 labels treated as paths:** Command labels were incorrectly treated as filesystem paths; subsequent commands use actual MoonBook-relative paths only.
- **Problem/Fix — command 010 stale anchors:** Stale patch anchors caused the command to stop; the repair was rebased on current file contents.

- command-003 exhausted step 8 after valid source edits without validation; this continuation completes that validation.
- The pure slice still does not claim end-to-end unbounded daemon behavior; strict codec/store/supervisor comes next.


- Problem/fix: The checkpoint idempotency test initially conflated event idempotency with checkpoint deduplication; it now checks exact-event replay as a no-op and distinct-event checkpoint deduplication separately.

- **Problem/Fix — Legacy async timeout flake after hardening:** After the post-hardening full native suite, the unrelated legacy async test `analysis_step_handler enforces timeout and token budget policies` failed once (1250/1251) at its 1ms timeout expectation. An immediate isolated rerun passed 1/1, identifying timing flakiness rather than a goal-runtime regression; no source or test edit was made.

- Problem/Fix (command-001): Invalid `priv fn`, deprecated suberror syntax, manual UInt16 hex indexing, and exhausting step 8 before compiler repair were replaced by modern MoonBit declarations, modern `priv suberror ... { ... }`, crypto hex helpers, and fail-fast compiler validation. Decode strictness and missing/extra-field rejection remain intentionally deferred to the decoder continuation.


# Command 006–009 problem/fix ledger

## Commands 006–009 (completed by command 009)

- **Problem:** Runtime codec constructors validated normalized copies but genesis hashing/storage still referenced caller-owned criteria, while stored events validated/serialized/stored the original mutable event and incompletely validated event-specific fields.
- **Fix:** Genesis now hashes and stores normalized criteria. Stored-event construction now copies first, derives identity from the copy, validates canonical identities and exhaustive variants, hashes the normalized event, and stores that copy. Focused tests cover equal session/goal IDs, invalid operation/checkpoint/cancel details, and mutation isolation for criteria, operations, evidence references, and alternatives.

- **Problem:** Provider stalls and local cancellation could be mistaken for aggregate goal exhaustion. **Fix:** Provider-stall remains a nonterminal external pause/observation, while local-cancel is terminal only when an explicit operator cancellation event is recorded; neither creates an implicit overall goal bound.
- **Problem:** Repeated legacy command runs exhausted at step 8 even while valid implementation work remained (including commands 001, 002, and 003), conflating controller-command allowance with goal completion. **Fix:** Command exhaustion is recorded as nonterminal continuation state. Work resumes in the next command, and the unbounded goal is settled only by explicit `Achieved`, `Blocked`, or `Cancelled` outcomes.

## Command 011 — semantic runtime digest regression

- Runtime-event semantic digests had incorrectly included the stable event ID and omitted protocol discriminator fields.
- The fixed-order semantic basis is now `{kind, protocol, contract, session_id, goal_id, payload}`; timestamp and stable ID are excluded.
- Constructors reject negative recording timestamps as timestamp-integrity violations. This is not a goal deadline or aggregate bound.
- Encoders are required to reconstruct values and enforce fixed/embedded IDs plus lowercase 64-hex digest integrity before normalized serialization.
- Operation timeout and output limits remain operation-local safeguards.

- **Problem/Fix — command 011 digest repair:** The first attempt only added `mooncode_goal_runtime_event_semantic_basis` and missed the constructor anchors, so it did not change stored-event digest behavior. This continuation preserves that history and actually wires the normalized event semantic basis into `new_mooncode_goal_runtime_stored_event`, excluding stable event IDs and `recorded_at` while retaining session, goal, and payload semantics; it also rejects negative event timestamps.

## Digest encoder repair (command 003 correction)

- **Problem:** Encoders trusted daemon-private envelope identity and `semantic_digest` fields, allowing forged records and post-construction nested mutation to serialize. The first focused tests also used `fail`/`noraise` inside effectful codec `try` blocks, producing a compile-time effect error, and incorrectly expected mutation of the caller-owned operations array after construction to invalidate the stored event even though the constructor correctly copies that array.
- **Fix:** Extracted raw `genesis_envelope_json` and `event_envelope_json` helpers. Encoders reconstruct through current constructors, require fixed/embedded IDs, validate lowercase 64-hex digests, compare recomputed digests, and serialize normalized values. Rejection tests now capture `Invalid` as a boolean and assert it, avoiding the compile effect error. The mutation test first proves caller mutation leaves nested encoding valid and byte-unchanged, then mutates the constructor-owned nested operations and verifies encoding rejects the resulting digest mismatch. Focused coverage retains forged IDs/digests and valid-byte stability.

## Formatter-snapshot recovery

A stale/deferred steer became a standalone turn, a regex repair corrupted 63 unrelated occurrences, and the command finished without validation. Recovery restored the last formatter snapshot and reapplied five AST-local edits with exact focused tests.

## Genesis `recorded_at` JSON-number decoding

MoonBit core's `FromJson` implementation for `Int64` accepts a JSON `String`, not `Json::Number`; using it on the valid numeric genesis timestamp `4294967296` therefore caused the two valid-decode failures. The codec now handles `Json::Number` directly: when the parser preserved an exact representation it passes that representation straight to `@string.parse_int64` (including syntax and overflow decisions), while representation-less doubles must be finite, integral, nonnegative, and at most `2^53 - 1` before exact conversion. The common result is then checked as nonnegative, with no aggregate goal bound or arbitrary maximum on exact represented integers.


## Codec test-file overwrite recovery

A hallucinated whole-test-file overwrite replaced validated codec coverage. The file was recovered from the formatter snapshot, then checked against the controller's expected suite. Prevention is to use small fresh sessions, apply narrow surgical patches rather than whole-file rewrites, and require controller verification of the resulting diff and focused validation receipts.

## Strict v1 codec decoder and event-matrix recovery

- **Problem:** A shell command ran `moon test ... 2>&1 | tail -80` without `pipefail`; `tail` exited 0 and masked the failed test. **Fix:** Run MoonCode test tools directly, or use shell pipelines with strict `pipefail`, and require controller verification of the canonical command.
- **Problem:** MoonCode repeatedly sent a native target to `moon fmt`, which does not accept a target. **Fix:** Run `moon fmt` without a target; use targets only for check and test.
- **Problem:** A broad short numeric-pattern edit touched the protected Int64 exact-representation branch and broke Int64-max decoding and syntax. **Fix:** The controller cancelled the turn, a fresh narrow session restored the exact `parse_int64(raw)` branch, and later prompts avoided broad numeric rewrites.
- **Problem:** A test-generation turn hallucinated nonexistent event APIs and overwrote a validated test region. **Fix:** Cancel before further formatting, restore the exact formatter snapshot through MoonCode, then re-add coverage in small typed slices using real `GoalRuntimeEvent` constructors.
- **Problem:** Event round-trip and schema-matrix attempts hallucinated wrong type names and constructors (`GoalRuntimeEvidence`, `GoalRuntimeBlockReason`, `PlannerDecisionMade`, and named enum arguments). **Fix:** Feed exact compiler diagnostics into fresh narrow MoonCode continuations and use the existing typed positional constructor patterns.
- **Problem:** The legacy runtime repeatedly exhausted at planner step 8 despite valid edits or even a final green tool result. **Fix:** Record the receipt as a nonterminal runtime defect and continue in a new command; it never means the goal is `Blocked`, `Achieved`, or `Cancelled`.
- **Problem:** A schema mutation assumed the canonical envelope began with `kind`, making replacements vacuous. **Fix:** Every mutation asserts `mutated != base`, which caught the bad needle; use the actual id-first encoder order.
- **Problem:** Store design exposed ambiguous achievement evidence because genesis allowed duplicate criterion text under different IDs. **Fix:** Require both criterion IDs and criterion texts to be canonical and unique before hashing or storing genesis.
- **Problem:** An append-only ledger turn used a whole-file write and deleted 175 historical lines. **Fix:** Recover the exact pre-turn bytes from the durable read record with byte/newline checks, then use this exact-tail edit; accept only an additions-only diff.
- **Evidence:** Focused native codec tests are 31/31; daemon native check reports 0 errors; `moon info` and formatting are clean; there is no `.mbti` interface diff; and an independent read-only audit found no P0/P1 blocker.
- **Invariant:** There is no aggregate goal bound: no token, turn, step, iteration, operation-count, LOC, deadline, or wall-time cap. `max_output_bytes` and `timeout_milliseconds` are operation-local containment only and cannot settle a goal.

## Canonical carrier boundary recovery

- **Problem:** The first carrier test draft regressed to obsolete tuple criteria, a five-argument stored-event constructor, nonexistent phases/events, unlabeled `String.replace`, and helpers without required error effects. **Fix:** Keep the structurally valid carrier source, replace the unvalidated test draft with the real typed positional codec patterns, and feed the exact compiler diagnostics into small continuation turns.
- **Problem:** The carrier encoder built guaranteed-valid JSON through `@json.parse`, leaking `Json::ParseError` outside its declared codec error effect. **Fix:** Construct the six-key contextual `Json` object directly after reconstructing and validating the embedded logical record.
- **Problem:** Two legacy commands again reached planner step 8 before validation completed. **Fix:** Preserve their edits and diagnostics as nonterminal continuation state; controller validation and a fresh MoonCode repair completed the slice.
- **Evidence:** The carrier suite passes 7/7, daemon native check reports 0 errors, and an independent read-only audit found no P0/P1 blocker. Exact canonical record bytes, every event/decision/phase, `Int64::MAX`, exact schemas, redundant-field checks, aggregate-alias rejection, and opaque operation input are covered.
- **Boundary:** This checkpoint is pure carrier encode/decode only. Physical journal append, locks, global cursor replay, stable-ID indexing, conflict detection, HTTP, and supervisor remain the next slices.

## Indexed scanner and literal-unbounded audit

- **Problem:** Reserved-carrier classification initially checked `record_kind` first, so a reserved payload beneath a malformed physical kind could be silently ignored. **Fix:** Inspect `payload.kind` first, then exact-validate the 10-key MoonLib envelope, carrier kind and contract, event kind, and the string types of command and client fields; reserved versions now fail closed.
- **Problem:** The first scanner expected outer `recorded_at` to be a JSON Number, while the actual carrier/appender copies the canonical decimal String. **Fix:** Accept only a canonical nonnegative Int64 String and compare it with the embedded record.
- **Problem:** Removing or corrupting a carrier's inner `kind` left carrier-only fields intact but could be misclassified as unrelated. **Fix:** Treat `logical_kind`, `semantic_digest`, or `canonical_record` as carrier-shaped evidence; then require a reserved String kind and fail closed on missing, non-string, or non-reserved values.
- **Recovery:** The legacy runtime repeatedly reached step 8 and retained parse and symbol typos despite useful edits. Every receipt remained a nonterminal pause, and fresh commands consumed the controller's exact diagnostics. One provider pause lacked a terminal journal row; cancellation targeted only that stuck legacy turn, preserving edits and journals, and a branch-local daemon was restarted.
- **Test recovery:** An appended scanner-test draft hallucinated `JournalRecord` and `DateTime` APIs and introduced malformed edits. MoonCode restored only that uncommitted tail exactly to `HEAD` through an explicit native tool call; the committed seven-test carrier file remained byte-exact. Scanner tests were then recreated in a separate new `wbtest` and repaired from compiler diagnostics to 6/6 green.
- **Literal-unbounded audit:** An independent audit found that the generic whole-file journal reader's 2 GiB guard and 32-bit `Int` sequence are artificial aggregate bounds; `Int64` is still finite. The next required migration is locked streaming JSONL replay plus an additive journal v2 canonical arbitrary-length decimal String sequence with a digit-carry successor, with dual v1/v2 readers deployed before v2 writes. This migration is explicitly open and is not claimed complete.
- **Evidence:** The carrier suite passes 7/7, the new scanner suite passes 6/6, and daemon check reports 0 errors. The current scanner checkpoint has no token, turn, step, retry, operation, deadline, elapsed-time, or output-total policy, but its physical v1 sequence/reader migration remains explicitly open.
- **Boundary:** Operation-local `max_output_bytes` and `timeout_milliseconds` do not settle goals.
