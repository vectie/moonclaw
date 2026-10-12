# Compare two saved job runs

When a repeated job behaves differently, compare saved journals side by side
without reopening the runtime. See steps that appeared or disappeared, changes
in recorded status or messages, event counts, and observed time spans. Follow
source filenames and physical line numbers back to the original evidence.

## Use

Build the native `cmd/compare_runs` package with the pinned toolchain and frozen
dependencies. Run its executable with explicit local `events.jsonl` files:

```sh
compare_runs saved/baseline/events.jsonl saved/candidate/events.jsonl \
  --baseline run-before --candidate run-after > comparison.json
compare_runs saved/combined.jsonl \
  --baseline run-before --candidate run-after --markdown > comparison.md
compare_runs --help
```

Files use the existing `JobRunEvent` JSONL shape written by
`SystemStore::append_run_event`, also accepted by `run_journal`. Multiple selected
runs may be in one file or span several files. Other runs are validated but not
compared. Use saved, stable files; the command does not lock a live writer or
create a coherent cross-file snapshot. Choose fresh output filenames: shell
redirection can overwrite files before the command starts.

The JSON schema is `moonclaw.job-run-comparison.v1`. Hosts can call
`@job_journal.compare_journal_runs(entries, baseline_run=..., candidate_run=...)`
after `parse_journal`, then use `to_json()` or `to_markdown()`.

## Read the comparison

- Run summaries name both run IDs and job IDs. Different jobs are allowed for
  deliberate cross-job comparison; matching step names do not prove equivalent
  semantics. A selected run ID attached to multiple job IDs is ambiguous and
  refused. Both run IDs must exist, be nonblank and differ.
- Steps align by exact, case-sensitive ID and are sorted lexically. `added` and
  `removed` mean absent from one supplied selection, not proof that a step was
  added to a plan, skipped or never executed. Events with no `step_id` contribute
  to each run summary and its run-level count, not a fabricated step.
- An observation includes event count, first and last complete source records,
  sorted event-type counts, observed `span`, and the most recent status-bearing
  event (`last_status` and `status_source`, omitted when none exists). A later
  status-free progress event does not erase an earlier status. At run level this
  may be a step's status; it is not a derived whole-run status.
- Records sort by stored timestamp, with ties retaining input file order and
  then physical line order. Identical records are retained. Repeated attempts
  with the same step ID are aggregated; the comparison does not invent attempt
  pairing, terminal states, active time or a performance verdict.
- `span` is last timestamp minus first timestamp in the producer's stored units.
  A single event spans zero. All span deltas are candidate minus baseline and
  use 64-bit arithmetic, including the full signed 32-bit timestamp range.
  JSON `span` and `span_delta` values are decimal strings, following the pinned
  MoonBit Int64 serializer; timestamps and event counts are JSON numbers. Units
  are not assumed to be milliseconds and clocks are not corrected. Compare time
  only when the producer's scales are compatible. Queue gaps and missing records
  can change the span without changing actual execution time.
- Matched steps include `span_delta`, `status_changed`, `event_counts_changed`
  (the entire type/count distribution), and `last_message_changed`. Comparisons
  use parsed JSON status equality and exact message strings. Added/removed steps
  omit these pair-only fields; `event_count_delta` treats the absent side as zero.
  `baseline` or `candidate` is omitted for the absent side.
- JSON preserves original parsed records in first/last/status provenance,
  including arbitrary status values, data and unknown fields. It is a summary,
  not an archive of every event. Keep the source files and use `run_journal` for
  full event exploration. JSON whitespace is not preserved. Markdown shows the
  summaries, last messages and source locations, escaping Markdown/HTML text.

## Limits and boundaries

At most 32 distinct filename arguments, 4 Mi UTF-16 code units per journal,
10,000 combined records. Files are read before the parser's text limit is checked.
Different paths to the same file are not detected as aliases; avoid supplying
both. No deduplication occurs. Malformed or incomplete records anywhere fail the
command, even if they belong to an unselected run. Error output uses stderr and
exit 1 with empty stdout; successful output exits 0. Empty/missing selections,
conflicting run identity, duplicate options and unknown options are errors.

This is local comparison of observations. It does not run, retry, cancel or
reconcile a job, infer live status, accept output, read referenced artifacts,
fetch URLs, authenticate evidence or redact private data. Unknown statuses remain
visible as recorded. Review journals and exports before sharing; no data is
transmitted by this command. Existing live views, artifact comparisons and
journal paging remain unchanged.

## Focused verification

`job_journal/comparison_test.mbt` covers alignment, source lineage, ties and
repeated observations, unknown/missing statuses, wide intervals, run-level and
cross-job observations, ambiguous selections and inert Markdown.
`scripts/test-compare-runs-cli.py BINARY NEW_OUTPUT_DIR` executes the native CLI
against retained synthetic journals, checks JSON/Markdown and reversal, confirms
unchanged inputs, and exercises invalid selections, files and options. This is
local fixture evidence, not live-provider or full-runtime qualification.
