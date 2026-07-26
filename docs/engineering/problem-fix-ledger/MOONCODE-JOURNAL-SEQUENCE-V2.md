# MoonCode journal sequence v2 recovery ledger

## Encountered failures

- **Compile failure:** `String.split` yields `StringView` records; the text replay
  boundary now converts only the active view with `to_owned()`. File `read_until`
  already yields an owned string and does not need conversion.
- **Iterator-consumption regression:** `String.split` returns a single-use iterator.
  Asking its length during iteration consumed the remaining records, and indexing
  the iterator does not compile. Materialize it once with `.collect()` before
  computing the committed line count; this restores empty/trailing-newline API
  compatibility while internal blank records remain corruption.
- **Semantic failure:** `MoonCodeJournalSequence::parse` accepted `"0"`, which
  allowed physical envelope sequence zero. The physical parser is now
  positive-only; `mooncode_journal_cursor_parse` alone accepts the nonnegative
  derived scan cursor.
- **Semantic correction:** physical envelope values and derived cursor values no
  longer share a parser, preserving sequence-zero rejection without preventing
  an empty journal from starting at cursor zero.

## Verification scope

Regression coverage includes mixed v1/v2 records, decimal sequences beyond
`Int64`, malformed and noncanonical spellings, internal blank records, trailing
newline handling, physical sequence-zero rejection, and preservation of the
exact last arbitrary-precision sequence.

- **Verification failure and fix:** the first native daemon test run exposed one
  stale cursor-zero test still calling the now-positive physical parser, plus
  three downstream HTTP status failures (`409` versus `200`/`404`). The cursor
  test was migrated to `mooncode_journal_cursor_parse`. The HTTP regressions came
  from consuming `String.split`’s single-use iterator while determining the
  trailing empty line; collecting once restored the expected behavior. The full
  daemon suite then passed 267/267 tests.

## Open migration boundaries

This slice makes validation and replay preserve exact arbitrary-precision
sequences. Production append and `mooncode_journal_entries` still use legacy
`Int` projections; they are the next migration slices and must not be treated as
exact until their focused regression tests pass.

## Superseding production migration completion

The historical boundary above is now closed. Production append and journal
entry consumers use exact v2 decimal strings, while v1 numeric envelopes remain
read-compatible. Append uses a locked line-oriented scan without whole-journal
materialization, exact successor carry, canonical JSONL, stable identity
deduplication, stable session locking, file flush, and supported parent-directory
synchronization. Active-state checks backed by durable lifecycle state logs
prevent post-archive/delete append or checkpoint resurrection. The log readers
stream committed entries without an aggregate-size cap, ignore torn marker tails,
and let the next writer repair them. Runtime-turn
holds the lifecycle gate shared per turn; runtime-service holds it from before
started persistence through terminal persistence; archive/restore/delete take it
exclusively. Shared-lock projections recheck state/location before reading the
selected snapshot and journal and exclude mutable live bindings from durable
rows. Conversation, stream, persisted-session snapshot, full-record,
external-listing, lifecycle, control, consumer, and capability surfaces carry
explicit post-migration contract IDs as appropriate; compact/listing rows and the
default list container do not. Watch v2 is a builder and negotiated write
contract, not a separately proven production emitter. Core proof is 75/75;
focused production append is 28/28. Append no longer materializes the whole
journal, but compatibility replay and HTTP response aggregation remain open
migrations. The prior 267/267 result remains historical evidence for the earlier
reader-only state.
