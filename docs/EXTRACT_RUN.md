# Extract and reopen one exact saved run

Use `extract_run` when `list_runs` finds a reused run ID in different jobs, or when you want a small self-contained journal for a single run. It combines up to 32 explicit saved JSONL files, selects the complete exact `(job_id, run_id)` pair and emits normal journal JSONL to stdout. Existing `run_journal`, `journal_csv`, and `compare_runs` can consume that selection.

```sh
extract_run saved/events.jsonl saved/archive.jsonl --job job-1 --run run-7 > new-run-7.jsonl
run_journal new-run-7.jsonl --run run-7 --markdown
```

Choose a new output filename. Shell `>` can truncate an existing file before the program runs; never redirect onto an input file. The command itself reads explicit inputs and only writes stdout/stderr. It does not open a destination, mutate the original journals, run a job, accept an artifact, reconcile an effect or authorize a retry.

Both `--job` and `--run` are mandatory exact case-sensitive string matches. A missing pair fails visibly, rather than creating a successful empty selection. IDs are not trimmed. All supplied observations are validated, even if unrelated to the chosen pair. Run-only filtering is intentionally not supported by this command. Flags do not select partial steps or time ranges: the output includes every supplied observation for the selected pair, regardless of state. This is complete only relative to the explicit files, not a claim that all records from a live run were supplied.

Output is chronological by recorded integer timestamp. Ties preserve input-file and physical-line order. Duplicate observations remain duplicates; overlapping journals are not deduplicated. Unknown fields, recorded job/run identity, unknown structured statuses, explicit nulls, missing fields, empty step IDs and Unicode text survive as parsed JSON values. A newline in a JSON string is escaped and does not create a second record. A successful extraction ends with a newline. Re-extracting the result with the same IDs is stable.

## Evidence and privacy limits

The output is ordinary JSONL, not an envelope or a runtime import command. Parsing it with existing tools is offline inspection only. It has new physical line numbers and a new source filename. Original whitespace, blank lines, JSON formatting, source filenames and original line provenance are not embedded in the output. Keep the original journals alongside the extracted file when investigating provenance. This does not claim byte-for-byte original-record preservation. Numeric representation follows the existing MoonBit JSON parser, including its floating-point precision limits; this is not a lossless raw-byte archive for arbitrary numeric literals.

Messages/data are not redacted, and recorded statuses are not independently verified. Inspect the output before sharing it. The selection has no live refresh, atomic multi-file snapshot or proof of completeness. Use stable saved inputs.

## Bounds and errors

Each input is bounded by the existing parser to 4 Mi UTF-16 code units; combined observations are limited to 10,000. Output is bounded to 4 Mi UTF-16 code units including final newlines so the same journal reader can reopen it. The bound includes reserialized records, which can differ in length from the original text. All output is prepared before stdout is written. It is not constant-memory streaming; file reads occur before their text limit checks.

Invalid options, missing IDs/files, duplicate literal input filenames, malformed unrelated records, no exact match, or exceeded bounds exit 1 with a diagnostic on stderr and no successful stdout. Input path aliases are not detected. Use `./--filename.jsonl` for names beginning with `--`. OS write failures may leave partial output; shell redirection is outside the command's file safety guarantees. `--help` alone prints usage and exits 0.

## Host API

`@job_journal.extract_run_journal(entries, job_id="job-1", run_id="run-7")` returns the bounded JSONL text and raises on invalid input or absent selection. `parse_journal` can reopen its successful result.

This addresses PRD MOONCLAW-B10 inspection/evidence reuse and the advanced-journal portion of MC-W07. It does not qualify the PRD's secret-redacted export, live recovery controls, provider execution or whole-product acceptance. Three added JS tests and the retained native CLI smoke cover this offline workflow.
