# Explore saved job journals

Inspect one or several local MoonClaw job journals without starting a gateway or
loading a runtime store. Merge parent and child observations, search messages,
filter a step or event type, and export a reviewable page as JSON or Markdown.

The input is the actual `JobRunEvent` JSONL written by
`SystemStore::append_run_event` at `runs/<run-id>/events.jsonl`. This is different
from `jsonl2md`, which formats agent conversation/trajectory logs. The existing
live UI timeline remains unchanged.

## Local workflow

After building `cmd/run_journal`, use its native executable:

```sh
"$BIN" saved/parent/events.jsonl saved/child/events.jsonl --limit 20 > first-page.json
"$BIN" saved/parent/events.jsonl saved/child/events.jsonl --run child --query receipt --markdown > child-receipts.md
"$BIN" saved/parent/events.jsonl --step prepare --type step.completed
"$BIN" saved/parent/events.jsonl --since 10 --until 30 --offset 0 --limit 10
"$BIN" --help
```

Use copies from a stopped runtime or a coherent backup when consistency matters.
The command does not lock a running store or guarantee an atomic snapshot across
files. Inputs are explicit filenames, not directory roots. It never follows a
path found inside an event, reads artifact contents, loads `SystemStore`, repairs
state, fetches a URL, or starts a job. Output goes to stdout; choose a fresh shell
redirection filename to avoid overwriting an input. Failures go to stderr with
exit status 1 and no partial stdout.

## Exploration rules

- Records are ordered by ascending stored timestamp. Ties keep input file order,
  then original physical line order. Blank lines count toward source line numbers
  but are not events. Identical observations are retained, not deduplicated.
- `--run`, `--step`, and `--type` match exact identifiers. `--query` searches the
  message only, case-insensitively. Filters combine with AND and run before paging.
- `--since` and `--until` are inclusive bounds in the producer's stored integer
  timestamp scale. There is no wall-clock conversion or correction of old records.
- `--offset` defaults to 0; `--limit` defaults to 100 and permits 1 through 1000.
  `total_events` counts all imported records; `matched_events` counts all records
  matching the filters; `returned_events` counts only this page. `next_offset`
  is present only when a further matching page exists. Reuse the same files and
  filters for the next page. An exhausted page is empty, never a runtime failure.
- The JSON schema is `moonclaw.job-journal-page.v1`. Each entry has `source`,
  one-based `line`, and its original parsed `record`. All event fields, including
  unknown future fields and raw status/data values, are preserved semantically.
  Whitespace and original JSON key formatting are not preserved. The page itself
  is an export, not an input journal or a store-restoration format.
- Markdown includes run/job/step identity, recorded status, message, timestamp and
  source line. It escapes Markdown/HTML metacharacters, flattens message newlines,
  and creates no file links. Structured `data` remains in the JSON export.

A historical `Succeeded` event does not certify current completion or owner
acceptance. Unknown outcomes remain as recorded; the explorer makes no current
status inference and offers no retry or reconcile controls. No broad PRD recovery,
redaction, or acceptance requirement is declared complete by this local feature.

## Bounds and privacy

At most 32 CLI input files, 4 Mi UTF-16 code units per parsed document, and 10,000
combined event records are supported. Files are read into memory before the text
limit is checked. The event projection follows the current producer's signed
32-bit `Int` timestamp. Malformed JSON or a malformed required event field anywhere
in an input fails the entire command, even if that line would be filtered out.
A partial final line is an error; retry with a stable saved copy. Optional `step_id`
and `status` can be absent. The supplied source name and physical line locate parse
errors; raw event contents are not included in parser diagnostics.

This is local inspection, not an automatic secret scrubber. Messages, arbitrary
`data`, unknown fields, identifiers and source paths may contain private data.
Review exported files before sharing them. The command does not transmit them.

## Build and verification

Use the pinned MoonBit toolchain, the module's exact frozen dependency graph,
private HOME/XDG directories and an absolute external target directory. In this
retained task, source `../environment.sh` from the source checkout; it establishes
`R`, `TARGET`, and the shared native lock. Ensure more than 4 GiB free before each
native phase:

```sh
. ../environment.sh
flock "$MOON_NATIVE_LOCK" moon -C "$R/source" --target-dir "$TARGET" build cmd/run_journal --target native --frozen --strip -j 1
moon -C "$R/source" --target-dir "$TARGET" test job_journal --target js --frozen --strip -j 1
flock "$MOON_NATIVE_LOCK" moon -C "$R/source" --target-dir "$TARGET" test job/journal_explorer_wbtest.mbt job/ui_events_wbtest.mbt --target native --frozen --strip -j 1
BIN="$TARGET/native/debug/build/cmd/run_journal/run_journal.exe"
```

Focused tests cover real producer serialization and persisted journals, unchanged
source files, equal timestamps, duplicate observations, mixed runs, optional
fields, filtering, pagination, unknown outcomes, empty and malformed journals,
bounds and inert Markdown. This is not full-runtime or live-provider qualification.

For side-by-side step and observation-span comparisons between two saved runs,
see [Compare saved runs](COMPARE_RUNS.md).

To inspect a run together with its exported output revisions and local content links,
see [Saved run review](RUN_REVIEW.md).

For an unpaged spreadsheet selection with the complete original records, use
[Saved journal CSV export](JOURNAL_CSV.md).
