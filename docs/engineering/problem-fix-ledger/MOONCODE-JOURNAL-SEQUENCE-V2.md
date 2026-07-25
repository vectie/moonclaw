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
