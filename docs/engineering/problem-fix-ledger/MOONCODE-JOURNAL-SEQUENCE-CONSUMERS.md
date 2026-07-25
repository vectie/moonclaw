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
