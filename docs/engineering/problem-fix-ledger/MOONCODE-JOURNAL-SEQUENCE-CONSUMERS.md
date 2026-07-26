# MoonCode journal exact-sequence consumers: problem/fix ledger

This ledger records the failures, fixes, and verification evidence from migrating
journal entry projection and durable stream replay from bounded integers to
exact decimal sequences. MoonCode authored the product, test, and documentation
changes; the controller supplied diagnostics and independently verified the
results.

## Delivered behavior

- `mooncode_journal_entries` validates the physical journal envelope and
  projects `journal_sequence` as a canonical decimal JSON string. The validated
  physical sequence overwrites any payload field with the same name.
- The durable stream accepts canonical nonnegative decimal `since` values,
  compares arbitrary-length sequences without integer conversion, and emits
  canonical decimal strings for `since`, `sequence`, `latest_sequence`, and
  `next_since`.
- Present zero or malformed projected sequences are rejected. Only an absent
  projected `journal_sequence` may use the synthetic array-index fallback used
  by tests and legacy in-memory projections.
- Wait, meta, event, and done envelopes identify the private
  `mooncode-stream.v2` sub-contract. The global `mooncode.v1` protocol remains
  unchanged. Number-only stream consumers must migrate to the v2 string fields.
- Response cursors are monotonic: `next_since` and the done cursor are
  `max(requested since, observed latest)` under exact sequence comparison.
  `meta.latest_sequence` continues to report the observed journal maximum.
- The new corruption effect from exact entry projection is propagated through
  `mooncode_session_custom_title`.

## Product and test failures fixed

### Bounded and shadowable journal-entry projection

- Failure: `mooncode_journal_entries` used `mooncode_json_int(..., default=0)`,
  which could not represent sequences beyond signed 64-bit range, silently
  defaulted malformed or missing data, and allowed payload shadowing.
- Fix: derive the sequence from the validated physical record with
  `mooncode_journal_sequence_from_record`, emit its canonical text as a JSON
  string, and overwrite the payload projection.
- Regression coverage: mixed v1/v2 records including
  `9223372036854775808`, payload shadowing, and physical zero/malformed
  rejection.

### Partial stream type migration

- Failure: the first stream edit left fourteen `MoonCodeJournalSequence`/`Int`
  mismatches across comparisons, envelope builders, and serialization.
- Fix: migrate all stream cursor parameters and comparisons together, then
  propagate the corruption effect through record building, latest/count
  helpers, JSONL, and SSE.
- Follow-up compiler failures and fixes:
  - Direct `String(...)` construction was read-only for this JSON type; use
    `.text().to_json()`.
  - Exact journal-entry projection introduced a raised store error; propagate
    it through the custom-title call chain.
  - A stale `next_since~` named argument caused one compiler error after the
    response-cursor refactor; remove the obsolete label.

### Numeric fixture precision

- Failure: an in-memory `Json` number beyond the exact host-number range had
  already rounded before the decoder observed it, creating an unexpected event.
- Fix: retain a small v1 numeric fixture for dual-read compatibility and use the
  v2 canonical string carrier for huge exact values. Raw parsed v1 numbers may
  preserve a lexical representation, but newly constructed in-memory numbers
  cannot be treated as an arbitrary-precision carrier.

### Rejection-test error handling

- Failure: `try?` returned a `Result`, and comparison with `None` also required
  unsupported `Eq`/`Show` implementations for the store error.
- Fix: use a focused helper that explicitly catches
  `MoonCodeGoalRuntimeStoreError::CorruptStore(_)` and fails on success or on a
  different error.

### Backward-moving stream cursor

- Audit failure: empty streams returned zero, and streams whose observed latest
  value was below the requested cursor moved `next_since` backward.
- Fix: compute the response cursor with exact `max(since, latest_sequence)`.
- Regression coverage: an empty stream with a huge cursor and a nonempty stream
  whose latest event is behind `since`; event and done `since` fields are also
  asserted.

### Unlabeled wire-shape migration

- Audit failure: sequence fields changed from JSON numbers to strings without a
  stream-specific contract label, so old consumers could misread the response.
- Fix: add `mooncode-stream.v2` to wait, meta, event, and done envelopes and
  assert the label in record, JSONL, and SSE tests.

## MoonCode/controller failures observed and recovered

- Multiple autonomous stage-2 turns stopped at the hard eight-step planner
  ceiling while work remained. The controller resumed with smaller diagnosed
  quanta and deterministic MoonCode tool calls; no interrupted turn was treated
  as completion.
- The planner guessed nonexistent paths:
  `cmd/daemon/mooncode_journal_sequence.mbt`, root-level
  `mooncode_stream.mbt`, and root-level `mooncode_stream_wbtest.mbt`. It also
  attempted an empty-path edit. The controller resolved the actual files before
  resuming.
- Some turns emitted `finish` after failed tools. Completion was ignored until
  independent compiler and test evidence existed.
- The MoonCode watcher repeatedly returned status 255 even when its embedded
  output claimed zero errors. Direct native `moon check` exposed real errors
  during the partial migration and later independently confirmed zero errors.
- One validation recipe bundled temporary-file creation and deletion, causing
  an unnecessary broad shell approval checkpoint. The controller rejected it
  and used the narrow native validation commands.
- An absolute `/Users/kq/.moon/bin/moon` invocation was correctly rejected by
  the selected-book path policy. Retrying the same validation through the
  relative `moon` command succeeded.

## Verification receipts

- Native compiler check: 0 errors.
- Focused journal streaming/projection tests: 18 passed, 0 failed.
- Focused durable-stream tests: 8 passed, 0 failed.
- Full daemon whitebox suite: 273 passed, 0 failed.
- `moon info && moon fmt`: succeeded; no generated `.mbti` interface changes.
- `git diff --check`: clean.

## Open boundaries

- Production append is not exact yet. It still materializes the journal,
  computes `mooncode_journal_last_sequence(records) + 1` through bounded `Int`,
  and writes MoonLib v1 numeric envelopes. It does not yet use
  `mooncode_journal_scan_for_append`, exact `.next()`, or
  `mooncode_journal_record_v2`. This stage therefore proves exact
  read/projection/stream behavior, not unbounded append or v2 writes.
- The handler now returns HTTP 400 for malformed or negative nonempty `since`
  and accepts huge canonical cursors, but this slice does not yet contain a
  focused HTTP-boundary test for those query cases.
- Direct wait-envelope cursor assertions are not isolated in a focused unit
  test, although the v2 wait contract is exercised by the full daemon suite.

## Production exact-v2 append and contract propagation

This section supersedes the historical open statement above that production
append was bounded and wrote v1. The old statement remains in place as an audit
trail.

- **Production writer:** append now acquires a stable cross-process session lock
  outside the movable session directory, repairs only a torn suffix, and uses a
  line-oriented scan without whole-journal materialization. The scan retains one
  complete JSONL line and its parsed record at a time, so memory scales with the
  largest single record but not with the whole journal. It delays duplicate suppression until validation
  completes, computes `cursor.next()` with decimal digit carry, and writes one
  canonical `moonsuite-conversation-journal.v2` line. Readers remain dual v1/v2.
- **Identity semantics:** direct `client_turn_id` has precedence; otherwise the
  first matching command identity is inherited. Foreign-session records fail
  closed. Missing timestamps, malformed snapshot cursors, and leaked goal-store
  errors normalize to the journal corruption contract.
- **Durability:** a successful append or duplicate retry requests ordinary
  journal file-data synchronization first. Non-Windows builds then request
  directory synchronization from the leaf through the filesystem anchor.
  Windows flushes the writable file only and has not run in a real Windows lane.
  Archive, restore, and delete use the same stable lock and are designed to
  prevent active/archive split-brain among cooperating processes. This is the
  OS-supported process and ordinary-crash boundary, not macOS `F_FULLFSYNC` or
  strongest sudden-power-loss proof.
- **Wire contracts:** conversation projection is
  `moonsuite-conversation.v3`; durable stream is `mooncode-stream.v2`; newly
  written `session.json` checkpoints are `mooncode-session-snapshot.v2`; and full
  diagnostic records are `mooncode-session-record.v2`. Only the outer
  `format=listing` envelope carries `mooncode-session-listing.v2`; its rows,
  compact rows, and the default session-list container do not. A full record
  derives its conversation as a sibling of `snapshot`; the checkpoint does not
  embed it. A legacy checkpoint may remain unchanged under the record's
  `snapshot` field until rewritten. Derived cursor fields are canonical decimal
  strings. Exact endpoint/watch builders reject empty, signed, leading-zero,
  fractional, exponent, and nondigit cursors.
- **Negotiation repair:** the daemon now delegates the fingerprinted native
  capability payload to `mooncode/core`. The capability surface, executable-book
  lifecycle, runtime-control, and runtime-consumer contracts were bumped to v2
  where their journal dependency changed; they expose current-write plus
  accepted-read journal IDs. Watch v2 plus legacy watch read IDs are advertised.
- **Open aggregate-memory boundary:** Exact append scanning no longer materializes
  the whole journal, but compatibility replay and the HTTP stream response still
  build arrays or aggregate payloads. Goal replay and HTTP-stream aggregate-memory
  independence remain separate migrations and are not claimed complete here.

## Runtime and validation failures recovered in this slice

- `/commands` first omitted `command_id`, then placed it at an unsupported top
  level; the accepted contract required it inside `packet`.
- A stale rejected turn was consumed before the replacement command.
- Autonomous turns repeatedly paused at the hard eight-tool step boundary, and
  one failed receipt followed partial successful edits. These receipts remained
  nonterminal; small deterministic MoonCode continuations resumed the same goal.
- Oversized tool results were truncated. The controller relied on file diffs,
  compiler output, and canonical test commands instead of receipt prose.
- Watcher status 255 and approval loops obscured diagnostics. Direct native
  `moon check` exposed the real errors; no approval checkpoint was treated as a
  goal bound.
- MoonCode skipped requested tests and made unsupported coverage claims. The
  controller independently ran focused and full suites.
- The first consumer migration produced 266/273 because stale numeric session
  projections remained. Exact string projections and labeled v2 shapes fixed
  them.
- Directory durability drafts used a `StringView` incorrectly and had catch
  precedence errors; exact compiler diagnostics produced owned paths and an
  exhaustive generic rethrow.
- A partial catch triggered a compiler warning treated as failure; a generic
  rethrow made the error boundary exhaustive.
- A later full run reached 282/283 because the capability endpoint template was
  stale; the canonical-decimal template and its test were corrected.
- The first portability audit found Windows directory flushing would call
  `FlushFileBuffers` on read-only directory handles, and a second audit found
  existence was not a durability anchor plus lifecycle move/delete races. The
  platform-gated directory sync, full ancestor chain, and stable external lock
  fixed those defects. A real Windows runtime lane is still required before
  claiming independently executed Windows durability proof.
- A stable lock alone still allowed a later append or snapshot checkpoint to
  recreate active storage after archive/delete. Active-state checks backed by a
  newline-committed lifecycle state log now reject stale writers. The reader
  streams committed entries without an aggregate-size cap, ignores a torn final
  marker suffix, lets the next writer repair it, reconciles interrupted transitions
  from the one surviving location, and rejects simultaneous active plus archived
  storage. First snapshot creation
  also syncs its parent chain.
- Runtime-turn holds a separate cross-process lifecycle gate shared per turn, and
  runtime-service holds it from before started persistence through success/failure
  terminal persistence. Archive, restore, and delete take it exclusively before
  idle/state checks and the stable storage lock. This closes the identified
  lifecycle TOCTOU for those native paths.
- Listing/show previously could mix a pre-move snapshot with a post-move journal
  or mutable live-binding fields. Per-row shared locking rechecks the selected
  store, reloads snapshot and journal within one lock domain, and omits moved
  rows. Active/archived durable rows exclude mutable live bindings; only an
  unpersisted `new` row may use one. The external listing envelope alone owns the
  v2 listing contract ID.
- Snapshot loading now validates its contract: a loaded persisted v2 checkpoint
  requires a canonical decimal-string `journal_sequence`. Persisted checkpoints
  with a missing contract ID or the v1 contract may dual-read numeric cursors; an
  absent snapshot synthesizes the current v2 cursor `"0"`, and unknown contract
  IDs fail closed. The legacy Int stream endpoint remains non-raising; exact-string
  validation is isolated to the new exact endpoint.
- A stale lifecycle-v1 capability description was corrected to v2 and a negative
  regression assertion rejects any v1 leak.

## Verification receipts for the production checkpoint

- Native daemon check: 0 errors.
- Core exact-contract suite: 75/75.
- Production journal streaming suite: 28/28.
- Same-process session-management/lifecycle/projection suite: 9/9.
- Runtime-service suite: 5/5.
- Session listing suite: 13/13.
- The historical 273/273 and intermediate 283/283 receipts remain valid for
  their exact source states.
- **Evidence boundary:** lifecycle, recovery, runtime-gate, and projection-race
  tests use same-process async scheduling; ancestor coverage verifies only the
  path plan. No multiprocess, crash/failpoint, sudden-power-loss, or real-Windows
  lane has run.
- **Final post-format receipts:** `moon info` and `moon fmt` succeeded; generated
  interface changes contain the expected exact cursor/watch/journal/session APIs
  while the legacy Int stream-endpoint wrapper remains source-compatible;
  `git diff --check` is clean; the daemon native suite passes 295/295; the full
  repository native suite passes 1356/1356.
