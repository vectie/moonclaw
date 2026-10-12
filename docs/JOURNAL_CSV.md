# Export saved observations for spreadsheet analysis

Use `journal_csv` to put every matching observation from saved MoonClaw run
journals into one sortable CSV. An operator can filter by run or step, group event
types, inspect unknown recorded outcomes, and keep the original event alongside
each row. No gateway, provider, runtime store or spreadsheet account is required.

The existing `run_journal` command exports paged JSON/Markdown. This workflow
exports the entire bounded selection, including more than 1,000 observations.
It does not paginate, truncate or collapse repeated observations.

## Use

Build `cmd/journal_csv` with the pinned native setup in the retained BUILD.md:

```sh
journal_csv saved/parent.jsonl saved/child.jsonl > observations.csv
journal_csv saved/events.jsonl --run run-17 --step inspect --query receipt > receipts.csv
journal_csv saved/events.jsonl --type step.progress --since 10 --until 30 > interval.csv
journal_csv --help
```

Choose a new output filename. Shell redirection can overwrite a file before the
command starts. Work from stable saved files; the command does not lock or take
an atomic snapshot of a concurrent runtime. Arguments are 1–32 distinct explicit
filenames. Use `./--name.jsonl` for a filename beginning with `--`. Different
spellings of the same underlying file are not detected as aliases.

In a spreadsheet's import dialog, choose UTF-8, comma separator and a double-quote
text delimiter. Import all columns other than `source_line` and `timestamp` as
text, with formula evaluation disabled. In particular, keep run/job/step IDs as
text so `00123` stays `00123`. Use the import dialog rather than blindly opening
untrusted CSV, and retain the original CSV when making spreadsheet edits. Some
spreadsheet applications limit cell lengths or change values during import/save.
No spreadsheet application's UI or formula evaluator was qualified here.

The native executable writes UTF-8 without a BOM, a fixed header and CRLF record
separators. Every data field is quoted; embedded double quotes are doubled.
Commas, CR/LF inside fields and Unicode are preserved. A header-only file means
no matching observations were supplied, not that the runtime did no work.

## Columns

- `source`, `source_line`: supplied filename and one-based physical journal line;
  blank input lines still count toward that line number
- `timestamp`: the producer's stored signed integer, without clock conversion
- `run_id`, `job_id`, `step_id`, `event_type`: recorded identifiers and event type;
  missing optional step IDs produce an empty convenience cell; an explicitly
  empty step ID also has an empty cell, while a null step ID is invalid input
- `status_json`: JSON serialization of the recorded status, including future
  structured values; absent optional status produces an empty cell, while an
  explicit JSON null is serialized as `null`
- `message`: the complete recorded message, including embedded newlines
- `data_json`: complete parsed event data encoded as JSON
- `record_json`: the complete original parsed event, including unknown fields;
  this preserves distinctions such as absent versus explicitly null status
- `text_prefixed_columns`: semicolon-separated names of columns to which this
  exporter added one leading apostrophe, in column order; empty when none

To reduce formula interpretation, text starting with `=`, `+`, `-`, `@` or an
apostrophe after any leading ordinary spaces receives one leading apostrophe.
A leading tab, CR, LF or BOM (also after ordinary spaces) receives the same
prefix. Validated numeric line/timestamp columns are not changed. This is a
conservative mitigation, not a universal spreadsheet security guarantee.

For lossless programmatic reading, use a CSV parser first. For each name in
`text_prefixed_columns`, remove exactly one leading apostrophe from that cell.
Then parse the `*_json` cells as JSON as needed. Do not remove apostrophes from
unlisted columns. This retains even originally apostrophe-prefixed text without
ambiguity. For example, a message `=1+2` exports as `'=1+2` with `message` listed;
an original `'note` exports as `''note`, also with `message` listed.

`record_json` preserves parsed semantics, not whitespace, duplicate JSON-key
spelling or original serialization. CSV is not a SystemStore backup or a runtime
restore format. A standard CSV reader can extract `record_json` values into a
new JSONL for the existing journal reader; this preserves event identities, but
the new filename and physical line numbers describe that new file. Original
source provenance remains in the original CSV columns.

## Selection and meaning

`--run`, `--step` and `--type` match exactly and case-sensitively. `--query` is a
case-insensitive substring search over messages only. `--since` and `--until`
are inclusive timestamp bounds in the original producer's integer scale. All
filters combine with AND. Ordering is ascending timestamp, then input file and
physical line order. Duplicate observations remain distinct rows. There are no
`--offset`, `--limit` or output-mode flags on this command.

Unknown and failed statuses remain recorded data. A historical `Succeeded`
status is not proof of current completion, artifact acceptance or a safe retry.
The CSV provides no execution controls, accepts no authority, reads no artifact
paths from events and makes no network requests. The shared selection code also
serves the existing explorer; its paging and output contracts are unchanged.

## Host API

```moonbit
let entries = @job_journal.parse_journal(saved_text, source="events.jsonl")
let csv = @job_journal.journal_csv(entries, run_id="run-17", query="receipt")
```

The library returns a complete CSV string and never writes or changes files.
It accepts the same optional run, step, event-type, message and time filters as
the CLI. It validates all supplied records, including those later filtered out.

## Bounds, errors and privacy

The existing reader permits 4 Mi UTF-16 code units per input file and 10,000
combined observations. Files are read before their text limits are checked.
CSV output is limited to 16 Mi UTF-16 code units, including quoting, prefixes,
header and CRLF separators. If the expansion exceeds that bound, narrow the
selection. A row is assembled before its output size is checked. This is not a
streaming or constant-memory exporter.

Malformed input, an invalid range/argument, unreadable file or exceeded bound
exits 1 with a diagnostic on stderr and no successful-output bytes written to
stdout. Success exits 0. An OS write failure can still interrupt output; do not
use a partially written file. Inputs are never modified by the command.

Messages, arbitrary data, unknown fields and filenames may contain private
information or secrets. The exporter does not redact them. Review the complete
CSV before sharing it. This feature advances offline inspection under MC-W01
and MOONCLAW-B10; it does not complete the PRD's broader secret-free evidence,
recovery or release-qualification requirements.

## Focused evidence

Four new API tests and the existing 20 `job_journal` tests pass with the pinned
JS target. `scripts/test-journal-csv-cli.py ABSOLUTE_BINARY NEW_OUTPUT_DIRECTORY`
retains native fixtures, CSV output, stdout/stderr and receipts. It uses Python's
standard CSV reader to validate quoting, reversible prefixes, original records,
Unicode and embedded newlines, filtered stable ordering, duplicate observations,
1,001-row full selection, a semantic JSONL round-trip, empty results, visible
errors and unchanged source hashes. These are local fixture observations, not
spreadsheet UI, live producer, provider or whole-runtime qualification.
